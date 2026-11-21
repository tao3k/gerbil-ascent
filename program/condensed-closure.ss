;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/iter for in-range)
        (only-in :gerbil-ascent/core/dependency-graph gerbil-ascent-graph-components/checkpoint)
        (only-in :gerbil-ascent/core/view-value make-relation-view make-part-visitors))
(export gerbil-ascent-condense-closure gerbil-ascent-extend-condensed-closure
        gerbil-ascent-remove-condensed-edge
        condensed-closure? condensed-closure-source condensed-closure-size
        gerbil-ascent-condensed-closure-view gerbil-ascent-condensed-witness
        gerbil-ascent-verify-condensed-witness condensed-witness-vertices)

;; Construction owns the ordinal map and adjacency, and publishes only after
;; every source row is admitted. A delta copies only the changing vectors.
(defstruct condensed-closure (source size positions labels adjacent members owner direct reach order) final: #t)
(defstruct condensed-order (labels runs count) final: #t)
(defstruct condensed-run (group start stop) final: #t)

;; This route bounds the dense bit sets by the number of admitted endpoints.
;; Wider graphs and unsupported inputs use the general positive evaluator.
(def dense-limit 8192)

(defrule (slot-bit i) (arithmetic-shift 1 i))
(def (fold-members bits consume state)
  (let loop ((remaining bits) (acc state))
    (if (zero? remaining) acc
      (let* ((other (bitwise-and remaining (- remaining 1)))
             (i (- (integer-length (bitwise-xor other remaining)) 1)))
        (loop other (consume i acc))))))

(def (build-condensed-order labels positions owner checkpoint!)
  (let (ordered (list-sort < (vector->list labels)))
    ;; Run boundaries share the immutable ordered label spine.
    (let scan ((rest ordered) (start ordered) (group #f) (runs []) (count 0))
      (checkpoint!)
      (if (null? rest)
        (if group
          (make-condensed-order ordered (reverse! (cons (make-condensed-run group start rest) runs))
            (+ count 1))
          (make-condensed-order ordered [] 0))
        (let (next (vector-ref owner (hash-get positions (car rest))))
          (cond ((not group) (scan (cdr rest) rest next runs count))
                ((= next group) (scan (cdr rest) start group runs count))
                (else (scan (cdr rest) rest next
                        (cons (make-condensed-run group start rest) runs) (+ count 1)))))))))

(def (visit-condensed-runs (order :- condensed-order) mask consume)
  (for-each
    (lambda ((run :- condensed-run))
      (when (bit-set? run.group mask)
        (let walk ((rest run.start))
          (unless (eq? rest run.stop)
            (consume (car rest))
            (walk (cdr rest))))))
    order.runs))

(def (gerbil-ascent-condense-closure source size visit-source checkpoint!)
  (let/cc decline
    (let ((positions (make-hash-table-eqv)) (pairs (make-hash-table-eqv))
          (vertices []) (edges []) (width 0) (count 0))
      (def (position! key)
        (unless (fixnum? key) (decline #f))
        (or (hash-get positions key)
            (let (i width)
              (when (= i dense-limit) (decline #f))
              (hash-put! positions key i)
              (set! vertices (cons key vertices))
              (set! width (+ i 1))
              i)))
      (visit-source
       (lambda (left right)
         (checkpoint!)
         (let* ((from (position! left)) (to (position! right))
                (pair (+ (* dense-limit from) to)))
           (when (hash-get pairs pair) (decline #f))
           (hash-put! pairs pair #t)
           (set! edges (cons pair edges))
           (set! count (+ count 1)))))
      (unless (= count size) (decline #f))
      (let ((adjacent (make-vector width [])) (owner (make-vector width #f)))
        (for-each (lambda (pair)
                    (checkpoint!)
                    (let ((from (quotient pair dense-limit)) (to (remainder pair dense-limit)))
                      (vector-set! adjacent from (cons to (vector-ref adjacent from)))))
                  edges)
        (let* ((members (list->vector (gerbil-ascent-graph-components/checkpoint adjacent checkpoint!)))
               (groups (vector-length members))
               (direct (make-vector groups 0)) (cyclic? #f))
          (for (g (in-range groups))
            (for-each (lambda (v) (checkpoint!) (vector-set! owner v g))
                      (vector-ref members g)))
          (for (v (in-range width))
            (let (g (vector-ref owner v))
              (for-each (lambda (target)
                          (checkpoint!)
                          (let (h (vector-ref owner target))
                            (when (= g h) (set! cyclic? #t))
                            (vector-set! direct g (bitwise-ior (slot-bit h) (vector-ref direct g)))))
                        (vector-ref adjacent v))))
          (unless cyclic? (decline #f))
          (let (reach (vector-copy direct))
            (let close ((g (- groups 1)))
              (when (>= g 0)
                (checkpoint!)
                (let (mask (vector-ref direct g))
                  (vector-set! reach g
                    (fold-members mask
                      (lambda (h out)
                        (checkpoint!)
                        (bitwise-ior out (vector-ref reach h)))
                      mask)))
                (close (- g 1))))
            (let (labels (list->vector (reverse! vertices)))
              (make-condensed-closure source size positions labels
                adjacent members owner direct reach
                (build-condensed-order labels positions owner checkpoint!)))))))))

(def (insert-adjacent edges target successor checkpoint!)
  (checkpoint!)
  (if (or (null? edges) (eqv? (car edges) successor))
    (cons target edges)
    (cons (car edges) (insert-adjacent (cdr edges) target successor checkpoint!))))

;; Appends share the exact previous source spine. A packed replacement
;; instead supplies the next target of this origin to preserve witness order.
;; An edge that can merge components must rebuild the quotient.
(def (gerbil-ascent-extend-condensed-closure (prior :- condensed-closure) source size row checkpoint!
                                           (packed-edit? #f))
  (let* ((left (car row)) (right (cadr row))
         (x (and (fixnum? left) (hash-get prior.positions left)))
         (y (and (fixnum? right) (hash-get prior.positions right))))
    (and x y (not (memv y (vector-ref prior.adjacent x)))
         (let ((a (vector-ref prior.owner x)) (b (vector-ref prior.owner y)))
           (and (or (= a b) (not (bit-set? a (vector-ref prior.reach b))))
                (let* ((adjacent (vector-copy prior.adjacent))
                       (direct (vector-copy prior.direct))
                       (reach (vector-copy prior.reach))
                       (suffix (bitwise-ior (slot-bit b) (vector-ref reach b))))
                  (let (edges (vector-ref adjacent x))
                    (vector-set! adjacent x
                      (if packed-edit?
                        (let (next (caddr row))
                          (insert-adjacent edges y (and next (hash-get prior.positions next)) checkpoint!))
                        (cons y edges))))
                  (vector-set! direct a (bitwise-ior (slot-bit b) (vector-ref direct a)))
                  (for (g (in-range (vector-length reach)))
                    (checkpoint!)
                    (when (or (= g a) (bit-set? a (vector-ref prior.reach g)))
                      (vector-set! reach g (bitwise-ior (vector-ref prior.reach g) suffix))))
                  (make-condensed-closure source size prior.positions prior.labels
                    adjacent prior.members prior.owner direct reach prior.order)))))))

(def (remove-adjacent edges target checkpoint!)
  (checkpoint!)
  (cond ((null? edges) [])
        ((= (car edges) target) (cdr edges))
        (else (cons (car edges) (remove-adjacent (cdr edges) target checkpoint!)))))

(def (has-cross-edge? adjacent members owner a b checkpoint!)
  (let/cc found
    (for-each
      (lambda (v)
        (for-each (lambda (target)
                    (checkpoint!)
                    (when (= (vector-ref owner target) b) (found #t)))
                  (vector-ref adjacent v)))
      (vector-ref members a))
    #f))

(def (withdrawal-reach direct prior-reach origin checkpoint!)
  (let ((reach (vector-copy prior-reach))
        (ready (make-vector (vector-length direct) #f)))
    (def (affected? g)
      (or (= g origin) (bit-set? origin (vector-ref prior-reach g))))
    (def (refresh! g)
      (checkpoint!)
      (unless (or (vector-ref ready g) (not (affected? g)))
        (let (mask (vector-ref direct g))
          (vector-set! reach g
            (fold-members mask
              (lambda (h bits)
                ;; SCC self bits represent nonempty internal paths. The
                ;; remaining edges form a DAG, in any ordinal order.
                (unless (= g h) (refresh! h))
                (if (= g h) bits (bitwise-ior bits (vector-ref reach h))))
              mask))
          (vector-set! ready g #t))))
    (for (g (in-range (vector-length reach))) (refresh! g))
    reach))

;; A cross-edge removal cannot split an SCC. Requiring both groups to
;; have internal cycles also keeps the vertex domain unchanged.
(def (gerbil-ascent-remove-condensed-edge (prior :- condensed-closure) source size row checkpoint!)
  (let ((x (hash-get prior.positions (car row))) (y (hash-get prior.positions (cadr row))))
    (and x y (memv y (vector-ref prior.adjacent x))
         (let ((a (vector-ref prior.owner x)) (b (vector-ref prior.owner y)))
           (and (not (= a b)) (bit-set? a (vector-ref prior.direct a)) (bit-set? b (vector-ref prior.direct b))
                (let ((adjacent (vector-copy prior.adjacent))
                      (direct prior.direct)
                      (reach prior.reach))
                  (vector-set! adjacent x (remove-adjacent (vector-ref adjacent x) y checkpoint!))
                  (unless (has-cross-edge? adjacent prior.members prior.owner a b checkpoint!)
                    (set! direct (vector-copy direct))
                    (vector-set! direct a (bitwise-and (vector-ref direct a) (bitwise-not (slot-bit b))))
                    (set! reach (withdrawal-reach direct reach a checkpoint!)))
                  (make-condensed-closure source size prior.positions prior.labels
                    adjacent prior.members prior.owner direct reach prior.order)))))))

;; Group masks are exact, including the self bit only for a nonempty path.
(def (gerbil-ascent-condensed-closure-view (index :- condensed-closure) version room checkpoint!)
  (let/cc decline
    (let* ((labels index.labels) (positions index.positions) (owner index.owner)
           (members index.members) (reach index.reach) (groups (vector-length members))
           (order index.order)
           (sizes (vector-map length members)) (target-counts (make-vector groups 0)) (count 0))
      (for (g (in-range groups))
        (checkpoint!)
        (let (targets (fold-members (vector-ref reach g)
                        (lambda (h n) (checkpoint!) (+ n (vector-ref sizes h))) 0))
          (vector-set! target-counts g targets)
          (set! count (+ count (* (vector-ref sizes g) targets)))
          (when (> count room) (decline #f))))
      (let ((targets (vector-map
                       (lambda (mask)
                         (delay-atomic
                           (list-sort <
                             (fold-members mask
                               (lambda (h out)
                                 (foldl (lambda (v rest) (cons (vector-ref labels v) rest))
                                        out (vector-ref members h)))
                               []))))
                       reach)))
        (def (reachable? left right)
          (and (fixnum? left) (fixnum? right)
               (let ((x (hash-get positions left)) (y (hash-get positions right)))
                 (and x y (bit-set? (vector-ref owner y) (vector-ref reach (vector-ref owner x)))))))
        (def (contains? row)
          (and (pair? row) (pair? (cdr row)) (null? (cddr row))
               (reachable? (car row) (cadr row))))
        (def (parts columns key consume)
          (def (matches? columns key left right)
            (or (null? columns)
                (and (equal? (if (= (car columns) 0) left right) (car key))
                     (matches? (cdr columns) (cdr key) left right))))
          (def (visit left (after #f) (single-origin? #f))
            (when (fixnum? left)
              (let (ordinal (hash-get positions left))
                (when ordinal
                  (let (group (vector-ref owner ordinal))
                    (def (emit right)
                      (when (matches? columns key left right) (consume [] left right)))
                    (if (and single-origin? (<= (condensed-order-count order)
                                              (vector-ref target-counts group)))
                      (visit-condensed-runs order (vector-ref reach group) emit)
                      (let skip ((remaining (force (vector-ref targets group))))
                        (if (and after (pair? remaining) (<= (car remaining) after))
                          (skip (cdr remaining))
                          (for-each emit remaining)))))))))
          (def (scan)
            (let (origin (memv 0 columns))
              (if origin (visit (list-ref key (- (length columns) (length origin)))
                                #f (null? (cdr columns)))
                (for-each visit (condensed-order-labels order)))))
          (def (visit-pair left right order first second)
            (when (reachable? left right)
              (consume [] left right)
              ;; The callback may edit either caller-owned binding list.
              ;; In that case the old visitor would keep reading the suffix.
              (unless (and (equal? columns order)
                           (match key
                             ([a b] (and (eq? a first) (eq? b second)))
                             (else #f)))
                (visit left right)))
            (void))
          (match columns
            ([0 1] (match key
                     ([left right] (visit-pair left right '(0 1) left right))
                     (else (scan))))
            ([1 0] (match key
                     ([right left] (visit-pair left right '(1 0) right left))
                     (else (scan))))
            (else (scan))))
        (make-relation-view index.source version 0 'total count groups
          (lambda (columns key consume) (parts columns key (lambda (_ a b) (consume (list a b)))))
          contains? #f (make-part-visitors parts parts))))))

(defstruct condensed-witness (identity version path) final: #t)

(def (condensed-witness-vertices (proof :- condensed-witness))
  (map values proof.path))

;; This read-only search records one nonempty path from the captured graph.
;; It charges every inspected edge and never returns a partial witness.
(def (gerbil-ascent-condensed-witness (index :- condensed-closure) version from to budget)
  (unless (and (exact-integer? budget) (>= budget 0))
    (error "invalid ASCENT closure witness budget" budget))
  (let ((x (and (fixnum? from) (hash-get index.positions from)))
        (y (and (fixnum? to) (hash-get index.positions to))))
    (and x y (bit-set? (vector-ref index.owner y) (vector-ref index.reach (vector-ref index.owner x)))
         (let/cc finish
           (let* ((width (vector-length index.labels))
                  (parents (make-vector width #f)) (queue (make-vector width)) (after 1))
             (vector-set! parents x x)
             (vector-set! queue 0 x)
             (let search ((head 0))
               (when (< head after)
                 (let (v (vector-ref queue head))
                   (for-each
                    (lambda (next)
                      (when (zero? budget) (finish #f))
                      (set! budget (- budget 1))
                      (when (= next y)
                        (let trace ((at v) (path (list to)))
                          (let (path (cons (vector-ref index.labels at) path))
                            (if (= at x) (finish (make-condensed-witness index.source version path))
                              (trace (vector-ref parents at) path)))))
                      (unless (vector-ref parents next)
                        (vector-set! parents next v)
                        (vector-set! queue after next)
                        (set! after (+ after 1))))
                    (vector-ref index.adjacent v)))
                 (search (+ head 1))))
             #f)))))

(def (gerbil-ascent-verify-condensed-witness (index :- condensed-closure) version proof)
  (and (condensed-witness? proof)
       (eq? index.source (condensed-witness-identity proof))
       (= version (condensed-witness-version proof))
       (let (path (condensed-witness-path proof))
         (and (pair? (cdr path))
              (let check ((left (hash-get index.positions (car path))) (rest (cdr path)))
                (and left
                     (or (null? rest)
                         (let (right (hash-get index.positions (car rest)))
                           (and (memv right (vector-ref index.adjacent left))
                                (check right (cdr rest)))))))))))
