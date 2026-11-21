;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/struct/rbtree RBTree rbtree-ref rbtree-put)
        (only-in :std/struct/queue Queue Queue-length queue-empty? enqueue! dequeue!)
        (only-in :gerbil-ascent/core/execution-control ascent-execution-checkpoint!))

(export gerbil-ascent-open-bound-reachability
        gerbil-ascent-bound-reachability-edit
        gerbil-ascent-bound-reachability-query
        gerbil-ascent-bound-reachability-path
        gerbil-ascent-bound-reachability-verify)

;; Published buckets are immutable. A witness retains only its private path and
;; version token, so keeping a witness does not keep the full graph alive.
(defstruct bound-index (base changes) final: #t)
(defstruct bound-graph (outgoing incoming size limit version) final: #t)
(defstruct bound-witness (version origin target reverse-path) final: #t)
(defstruct backward-chain (path) final: #t)

(def (check-bound-limit limit)
  (unless (or (eqv? limit +inf.0) (and (exact-integer? limit) (>= limit 0)))
    (error "invalid ASCENT bound reachability limit" limit)))

(def (bound-work limit)
  (check-bound-limit limit)
  (ascent-execution-checkpoint!)
  (lambda ()
    (ascent-execution-checkpoint! 1 0)
    (when (= limit 0) (error "ASCENT bound reachability work exhausted"))
    (set! limit (- limit 1))))

(def (check-endpoints origin target)
  (unless (and (fixnum? origin) (fixnum? target))
    (error "ASCENT bound reachability requires fixnum endpoints" origin target)))

(def (neighbors (index :- bound-index) vertex)
  (or (rbtree-ref index.changes vertex #f)
      (hash-ref index.base vertex [])))

(def (compare-vertex a b)
  (cond ((fx< a b) -1) ((fx> a b) 1) (else 0)))

(def (gerbil-ascent-open-bound-reachability rows edge-limit: (edge-limit +inf.0)
                                            work-limit: (work-limit +inf.0))
  (check-bound-limit edge-limit)
  (let ((step! (bound-work work-limit))
        (outgoing (make-hash-table-eqv))
        (incoming (make-hash-table-eqv))
        (seen (make-hash-table))
        (size 0))
    ;; The lagging cursor detects cyclic input while every admitted row still
    ;; passes through the normal cancellation and work check.
    (let loop ((rows rows) (lag rows) (advance-lag? #f))
      (match rows
        ([] (void))
        ([[origin target] . tail]
         (step!)
         (when (eq? tail lag) (error "cyclic ASCENT bound reachability rows"))
         (check-endpoints origin target)
         (let (key (cons origin target))
           (unless (hash-get seen key)
             (when (= size edge-limit) (error "ASCENT bound reachability edge limit exhausted"))
             (hash-put! seen key #t)
             (hash-update! outgoing origin (lambda (bucket) (cons target bucket)) [])
             (hash-update! incoming target (lambda (bucket) (cons origin bucket)) [])
             (set! size (+ size 1))))
         (loop tail (if advance-lag? (cdr lag) lag) (not advance-lag?)))
        (else (error "invalid ASCENT bound reachability rows"))))
    (ascent-execution-checkpoint!)
    (make-bound-graph (make-bound-index outgoing (RBTree compare-vertex))
                      (make-bound-index incoming (RBTree compare-vertex))
                      size edge-limit (gensym 'bound-graph))))

(def (edit-bucket before target present? read! step!)
  (let walk ((rest before) (prefix []))
    (cond
      ((null? rest)
       (if present? (values (cons target before) 1) (values before 0)))
      (else
       (read!)
       (if (= (car rest) target)
         (if present? (values before 0)
           (let restore ((prefix prefix) (tail (cdr rest)))
             (if (null? prefix) (values tail -1)
               (begin (step!) (restore (cdr prefix) (cons (car prefix) tail))))))
         (walk (cdr rest) (if present? [] (cons (car rest) prefix))))))))

(def (put-bucket (index :- bound-index) key bucket)
  (make-bound-index index.base (rbtree-put index.changes key bucket)))

;; Returns the new graph, the number of changed buckets, and old edges read.
(def (gerbil-ascent-bound-reachability-edit (graph :- bound-graph) origin target present?
                                            work-limit: (work-limit +inf.0))
  (check-endpoints origin target)
  (unless (boolean? present?) (error "invalid ASCENT bound reachability edit" present?))
  (let ((step! (bound-work work-limit)) (reads 0))
    (def (read!) (step!) (set! reads (+ reads 1)))
    (let-values (((forward change) (edit-bucket (neighbors graph.outgoing origin) target present? read! step!)))
      (let (size (+ graph.size change))
        (when (> size graph.limit) (error "ASCENT bound reachability edge limit exhausted"))
        (if (zero? change)
          (begin
            (ascent-execution-checkpoint!)
            (values (make-bound-graph graph.outgoing graph.incoming size graph.limit (gensym 'bound-graph)) 0 reads))
          (let-values (((backward mirrored) (edit-bucket (neighbors graph.incoming target) origin present? read! step!)))
            (unless (= mirrored change) (error "inconsistent ASCENT bound reachability index"))
            (let ((next-out (put-bucket graph.outgoing origin forward))
                  (next-in (put-bucket graph.incoming target backward)))
              (ascent-execution-checkpoint!)
              (values (make-bound-graph next-out next-in size graph.limit (gensym 'bound-graph)) 2 reads))))))))

;; Returns a positive witness or #f, and the number of searched edges. A
;; same-endpoint query starts from a real edge just like other bindings.
(def (gerbil-ascent-bound-reachability-query (graph :- bound-graph) origin target
                                              work-limit: (work-limit +inf.0))
  (check-endpoints origin target)
  (let* ((step! (bound-work work-limit))
         (starts (neighbors graph.outgoing origin))
         (ends (neighbors graph.incoming target))
         (reads 0))
    (let/cc done
      (def (finish witness)
        (ascent-execution-checkpoint!)
        (done witness reads))
      (def (hit path)
        (finish (make-bound-witness graph.version origin target path)))
      (when (or (null? starts) (null? ends)) (finish #f))
      (let* ((first (and (null? (cdr starts))
                         (begin (step!) (set! reads 1) (car starts)))))
        (when (and first (= first target)) (hit (list target origin)))
        (let* ((two-sided? (not (= origin target)))
             (left-root (list origin)) (right-root (list target))
             (seen (make-hash-table-eqv)) (left (Queue))
             (right (and two-sided? (Queue)))
             (backward-first? (and two-sided? (pair? (cdr starts)) (null? (cdr ends)))))
          (def (meet forward backward)
            ;; The tails share the meeting vertex. Only the backward suffix
            ;; needs to be consed onto the existing reversed prefix.
            (let stitch ((path forward) (rest (cdr backward)))
              (if (null? rest) (hit path)
                (begin (step!) (stitch (cons (car rest) path) (cdr rest))))))
          (def (advance pending index root root-bucket backward?)
            (let* ((path (dequeue! pending))
                   (bucket (if (eq? path root) root-bucket
                             (begin (step!) (neighbors index (car path))))))
              (for-each
                (lambda (next)
                  (step!)
                  (set! reads (+ reads 1))
                  (let (entry (hash-get seen next))
                    (cond
                      ((not entry)
                       (let (chain (cons next path))
                         (hash-put! seen next (if backward? (make-backward-chain chain) chain))
                         (enqueue! pending chain)))
                      (backward?
                       (when (pair? entry) (meet entry (cons next path))))
                      ((not (pair? entry))
                       (meet (cons next path) (backward-chain-path entry))))))
                bucket)))
          ;; On a self-query the reverse root only marks the target. It has
          ;; no queue, so a match still requires an edge into that vertex.
          (hash-put! seen target (make-backward-chain right-root))
          (when right
            (hash-put! seen origin left-root)
            (enqueue! right right-root))
          (if first
            (unless (= first origin)
              (let (chain (cons first left-root))
                (hash-put! seen first chain)
                (enqueue! left chain)))
            (enqueue! left left-root))
          (let visit ((prefer-backward? backward-first?))
            (cond
              ((or (queue-empty? left) (and right (queue-empty? right))) (finish #f))
              ((and right (or prefer-backward? (< (Queue-length right) (Queue-length left))))
               (advance right graph.incoming right-root ends #t)
               (visit #f))
              (else
               (advance left graph.outgoing left-root starts #f)
               (visit #f)))))))))

(def (gerbil-ascent-bound-reachability-path (witness :- bound-witness) work-limit: (work-limit +inf.0))
  (let (step! (bound-work work-limit))
    (let loop ((rest witness.reverse-path) (path []))
      (if (null? rest)
        (begin (ascent-execution-checkpoint!) path)
        (begin (step!) (loop (cdr rest) (cons (car rest) path)))))))

(def (gerbil-ascent-bound-reachability-verify (graph :- bound-graph) (witness :- bound-witness)
                                               work-limit: (work-limit +inf.0))
  (let (step! (bound-work work-limit))
    (def (contains? from to)
      (let search ((rest (neighbors graph.outgoing from)))
        (and (pair? rest)
             (begin (step!) (or (= (car rest) to) (search (cdr rest)))))))
    (and (eq? graph.version witness.version)
         (let (path witness.reverse-path)
           (and (pair? (cdr path)) (= (car path) witness.target)
                (let walk ((rest path))
                  (if (null? (cdr rest))
                    (and (= (car rest) witness.origin)
                         (begin (ascent-execution-checkpoint!) #t))
                    (and (contains? (cadr rest) (car rest)) (walk (cdr rest))))))))))
