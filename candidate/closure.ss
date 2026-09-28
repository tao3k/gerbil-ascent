;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Scheme implementation of the selected Ascent binary closure's shortest
;;; source support. Fact labels here are caller-owned integers; MRR retains
;;; semantic FactId, rule-pack, generation, and admission authority.

(import (only-in :clan/poo/object .o))

(export gerbil-ascent-closure-candidates)

(def (support<? left right)
  (let loop ((left left) (right right))
    (cond ((null? left) (pair? right))
          ((null? right) #f)
          ((< (car left) (car right)) #t)
          ((> (car left) (car right)) #f)
          (else (loop (cdr left) (cdr right))))))

(def (better-support? candidate current)
  (or (not current)
      (< (car candidate) (car current))
      (and (= (car candidate) (car current))
           (support<? (reverse (cdr candidate))
                      (reverse (cdr current))))))

(def (source-index facts radix)
  (let ((index (make-vector radix []))
        (nodes (make-u8vector radix 0))
        (node-count 0)
        (ids (make-hash-table)))
    (def (mark-node! node)
      (when (= (u8vector-ref nodes node) 0)
        (u8vector-set! nodes node 1)
        (set! node-count (+ node-count 1))))
    (for-each
     (lambda (fact)
       (let ((pair (car fact)) (id (cdr fact)))
         (unless (and (exact-integer? pair) (<= 0 pair) (< pair (* radix radix))
                      (exact-integer? id) (<= 0 id))
           (error "invalid ASCENT source fact" fact))
         (when (hash-get ids id)
           (error "duplicate ASCENT source fact label" id))
         (hash-put! ids id #t)
         (let ((from (quotient pair radix)) (to (modulo pair radix)))
           (mark-node! from)
           (mark-node! to)
           (vector-set! index from
                        (cons (cons to id) (vector-ref index from))))))
     facts)
    (values index node-count)))

(def (shortest-supports index origin radix)
  (let ((best (make-vector radix #f)))
    ;; A path is (depth . reversed-labels): extending it shares the existing
    ;; list instead of copying an increasingly long forward path per edge.
    (let loop ((frontier (list (cons origin (cons 0 [])))))
      (unless (null? frontier)
        (let (next [])
          (for-each
           (lambda (state)
             ;; A superseded path cannot improve any descendant through the
             ;; same suffix. Identity checks discard its queued expansion.
             (when (or (= (car state) origin)
                       (eq? (cdr state) (vector-ref best (car state))))
               (for-each
                (lambda (edge)
                  (let* ((target (car edge))
                         (parent (cdr state))
                         (support (cons (+ 1 (car parent))
                                        (cons (cdr edge) (cdr parent))))
                         (current (vector-ref best target)))
                    (when (better-support? support current)
                      (vector-set! best target support)
                      ;; A cycle can prove (origin, origin), but following it
                      ;; cannot improve any shortest path from origin.
                      (unless (= target origin)
                        (set! next (cons (cons target support) next))))))
                (vector-ref index (car state)))))
           frontier)
          (loop (reverse next)))))
    best))

(def (closure-candidates facts radix max-input-facts max-derived-pairs max-results)
  (unless (and (exact-integer? radix) (> radix 1)
               (exact-integer? max-input-facts) (> max-input-facts 0)
               (exact-integer? max-derived-pairs) (> max-derived-pairs 0)
               (exact-integer? max-results) (> max-results 0))
    (error "invalid ASCENT closure bounds"))
  (when (> (length facts) max-input-facts)
    (error "ASCENT input fact budget exceeded" (length facts) max-input-facts))
  (let-values (((index node-count) (source-index facts radix)))
    (when (> (* node-count node-count) max-derived-pairs)
      (error "ASCENT derived pair budget exceeded"
             (* node-count node-count) max-derived-pairs))
    ;; A source-labelled breadth-first traversal already computes both the
    ;; minimum distance and canonical support. Visiting origins and targets
    ;; in numeric order publishes the same canonical pair order without a
    ;; second closure materialization or a result sort.
    (let* ((all
            (let origin-loop ((origin 0) (result []))
              (if (= origin radix)
                (reverse result)
                (let ((paths (and (pair? (vector-ref index origin))
                                  (shortest-supports index origin radix))))
                  (let target-loop ((target 0) (result result))
                    (if (= target radix)
                      (origin-loop (+ origin 1) result)
                      (let (path (and paths (vector-ref paths target)))
                        (if path
                          (let (depth (car path))
                            (target-loop
                             (+ target 1)
                             (cons (.o (pair (+ (* origin radix) target))
                                       (distance depth)
                                       (support (reverse (cdr path)))
                                       (rule (if (= depth 1)
                                               'base 'transitive)))
                                   result)))
                          (target-loop (+ target 1) result)))))))))
           (truncated? (> (length all) max-results)))
      (.o (status (if truncated? 'output-truncated 'complete))
          (input-count (length facts))
          (candidates (if truncated? (take all max-results) all))))))

(def (gerbil-ascent-closure-candidates
      source-facts radix max-input-facts max-derived-pairs max-results)
  (closure-candidates source-facts radix
                      max-input-facts max-derived-pairs max-results))
