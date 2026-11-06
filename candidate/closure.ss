;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Scheme implementation of the selected Ascent binary closure's shortest
;;; source support. Fact labels here are caller-owned integers; MRR retains
;;; semantic FactId, rule-pack, generation, and admission authority.

(import (only-in :gerbil/runtime/gambit fx+)
        (only-in :clan/poo/object .o)
        (only-in :std/list/list-builder with-list-builder))

(export gerbil-ascent-closure-candidates)

;; : (-> SourceLabels SourceLabels Boolean)
(def (support<? left right)
  (let loop ((left left) (right right))
    (cond ((null? left) (pair? right))
          ((null? right) #f)
          ((< (car left) (car right)) #t)
          ((> (car left) (car right)) #f)
          (else (loop (cdr left) (cdr right))))))

;; : (-> RankedSupport (Maybe RankedSupport) Boolean)
(def (better-support? candidate current)
  (or (not current)
      (< (car candidate) (car current))
      (and (= (car candidate) (car current))
           (support<? (reverse (cdr candidate))
                      (reverse (cdr current))))))

;;; One admission owns the occupied nodes and ordered adjacency. Dense arrays
;;; use dense invocation-local offsets after source validation. Absent domain
;;; slots consume neither graph storage nor result-selection work.
;; source-index
;; : (forall (label) (-> [(Pair Nat label)] Nat (Values (Adjacency label) (Vector Nat))))
;; : (-> SourceFacts Nat (Values Adjacency OrderedNodes))
;; | doc m%
;;     Validate facts and labels before choosing the occupied-domain layout.
;;     Adjacency retains reversed source order for canonical support comparison.
;;     The numeric domain bounds IDs; its absent slots need no storage.
;;
;;     # Examples
;;
;;     ```scheme
;;     (source-index '((1 . 7)) 8)
;;     ;; => adjacency and ordered occupied nodes #(0 1)
;;     ```
;;   %
(def (source-index facts radix)
  (let ((index (make-hash-table-eqv)) (nodes (make-hash-table-eqv))
        (ids (make-hash-table)))
    (for-each
     (lambda (fact)
       (with ([pair . id] fact)
         (unless (and (exact-integer? pair) (<= 0 pair) (< pair (* radix radix))
                      (exact-integer? id) (<= 0 id))
           (error "invalid ASCENT source fact" fact))
         (when (hash-get ids id) (error "duplicate ASCENT source fact label" id))
         (hash-put! ids id #t)
         (let ((from (quotient pair radix)) (to (modulo pair radix)))
           (hash-put! nodes from #t) (hash-put! nodes to #t)
           (hash-put! index from (cons (cons to id) (or (hash-get index from) [])))))) facts)
    (let* ((ordered (list->vector (list-sort < (hash-keys nodes))))
           (count (vector-length ordered))
           (adjacency (make-vector count [])))
      ;; Admission is complete: reuse membership as the private ID-to-offset
      ;; map. No caller observes this table or depends on its former booleans.
      (for-each (lambda (position)
                  (hash-put! nodes (vector-ref ordered position) position)) (iota count))
      (for-each
       (lambda (position)
         (vector-set! adjacency position
           (map (lambda (edge) (cons (hash-ref nodes (car edge)) (cdr edge)))
                (or (hash-get index (vector-ref ordered position)) [])))) (iota count))
      (values adjacency ordered))))


;; shortest-supports
;; : (forall (label) (-> (Adjacency label) Nat Nat (SupportTable label)))
;; : (-> Adjacency Origin Nat SupportTable)
;; | doc m%
;;     Traverse source-labelled frontiers and retain shortest canonical paths.
;;     Dense offsets represent only occupied IDs, including sparse input domains.
;;     Superseded paths cannot expand, and cycles establish nonempty support.
;;
;;     # Examples
;;
;;     ```scheme
;;     (shortest-supports adjacency 0 radix)
;;     ;; => founded support paths, without a zero-edge origin claim
;;     ```
;;   %
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
                         (support (cons (fx+ 1 (car parent))
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


;; closure-candidates
;; : (forall (label) (-> [(Pair Nat label)] Nat Nat Nat Nat (ClosureReceipt label)))
;; : (-> SourceFacts Nat InputCap PairCap ResultCap ClosureReceipt)
;; | doc m%
;;     Admit the full source graph, compute canonical shortest supports and
;;     publish numeric pair order before result truncation. Pair admission uses
;;     the square of occupied node count, independent of domain padding.
;;
;;     # Examples
;;
;;     ```scheme
;;     (closure-candidates '((1 . 7)) 8 1 4 4)
;;     ;; => a complete receipt containing pair 1 with support '(7)
;;     ```
;;   %
(def (closure-candidates facts radix max-input-facts max-derived-pairs max-results)
  (unless (and (exact-integer? radix) (> radix 1)
               (exact-integer? max-input-facts) (> max-input-facts 0)
               (exact-integer? max-derived-pairs) (> max-derived-pairs 0)
               (exact-integer? max-results) (> max-results 0))
    (error "invalid ASCENT closure bounds"))
  (when (> (length facts) max-input-facts)
    (error "ASCENT input fact budget exceeded" (length facts) max-input-facts))
  (let-values (((index occupied) (source-index facts radix)))
    (when (> (* (vector-length occupied) (vector-length occupied)) max-derived-pairs)
      (error "ASCENT derived pair budget exceeded"
             (* (vector-length occupied) (vector-length occupied)) max-derived-pairs))
    ;; Native list construction owns ordered publication. Numeric sorting of
    ;; occupied/reached keys supplies order; hash iteration never publishes.
    (let* ((all
            (with-list-builder (collect)
              (for-each
               (lambda (origin)
                 (when (pair? (vector-ref index origin))
                   (let* ((paths (shortest-supports index origin (vector-length occupied)))
                          (targets (iota (vector-length occupied))))
                     (for-each
                      (lambda (target)
                        (let (path (vector-ref paths target))
                          (when path
                            (let (depth (car path))
                              (collect (.o (pair (+ (* (vector-ref occupied origin) radix) (vector-ref occupied target)))
                                           (distance depth)
                                           (support (reverse (cdr path)))
                                           (rule (if (= depth 1) 'base 'transitive)))))))) targets))))
               (iota (vector-length occupied)))))
           (truncated? (> (length all) max-results)))
      (.o (status (if truncated? 'output-truncated 'complete))
          (input-count (length facts))
          (candidates (if truncated? (take all max-results) all))))))

;; gerbil-ascent-closure-candidates
;; : (forall (label) (-> [(Pair Nat label)] Nat Nat Nat Nat (ClosureReceipt label)))
;; : (-> SourceFacts Nat InputCap PairCap ResultCap ClosureReceipt)
;; | doc m%
;;     Compute the bounded public shortest-source-support receipt. Source IDs
;;     and labels retain exact integer semantics across sparse domains.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-closure-candidates '((1 . 7)) 8 1 4 4)
;;     ;; => complete source-labelled closure receipt
;;     ```
;;   %
(def (gerbil-ascent-closure-candidates
      source-facts radix max-input-facts max-derived-pairs max-results)
  (closure-candidates source-facts radix
                      max-input-facts max-derived-pairs max-results))
