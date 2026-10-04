;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Native dependency invalidation selects components; the evaluator owns
;;; reuse capsules, mutable rows, budget accounting and atomic publication.
(import (only-in :clan/poo/object .ref)
        (only-in "scheme-checked.ss" relational-stable-procedure?)
        (only-in "positive.ss" gerbil-ascent-positive-plan)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-set-storage-provider))
(export gerbil-ascent-update-selection gerbil-ascent-active-prefix
        gerbil-ascent-update-active-plans)

;; gerbil-ascent-update-selection
;; : (forall (a) (-> a a Vector (Maybe Vector)))
;;   : (-> SourceSnapshot Program Analysis (Maybe AffectedRelations))
;;   | doc m%
;;       Compare source logs and close the affected set through native plans.
;;       Only built-in storage and registered closed procedures qualify. An
;;       opaque callback/provider returns false and keeps full recomputation.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-update-selection old prospective analysis)
;;       ;; => a fresh affected-relation bitmap, or #f for an opaque provider
;;       ```
;;     %
(def (gerbil-ascent-update-selection previous candidate analysis)
  (let* ((relations (.ref candidate 'relations))
         (old-relations (vector->list previous))
         (plans (vector-ref analysis 2))
         (count (length relations))
         (affected (make-vector count #f)))
    (def (pure-terms? terms)
      (andmap (lambda (term) (memq (.ref term 'kind) '(variable wildcard literal))) terms))
    (def (stable-clause? clause)
      (case (.ref clause 'ascent-clause-kind)
        ((atom negation) (pure-terms? (.ref clause 'terms)))
        ((aggregate) (and (pure-terms? (.ref clause 'terms))
                          (not (.ref clause 'output-pattern))
                          (relational-stable-procedure? (.ref clause 'aggregate))))
        ((guard) (relational-stable-procedure? (.ref clause 'predicate)))
        ((binding) (relational-stable-procedure? (.ref clause 'compute)))
        (else #f)))
    (let (eligible?
          (and (= count (length old-relations))
               (andmap (lambda (relation)
                         (if (eq? (.ref relation 'storage-kind) 'lattice)
                             (relational-stable-procedure? (.ref relation 'join))
                             (eq? (.ref relation 'storage-provider)
                                  gerbil-ascent-set-storage-provider))) relations)
               (andmap (lambda (rule)
                         (and (andmap (lambda (head) (pure-terms? (.ref head 'terms)))
                                      (.ref rule 'heads))
                              (andmap stable-clause? (.ref rule 'body))))
                       (.ref candidate 'rules))))
      (if (not eligible?)
          #f
          (begin
            (for-each
             (lambda (old new index)
               (unless (equal? (append (car old) (reverse (cdr old))) (.ref new 'rows))
                 (vector-set! affected index #t)))
             old-relations relations (iota count))
            (propagate-affected! plans affected)
            affected)))))

;; propagate-affected!
;; : (forall (p) (-> [p] (Vector Boolean) Void))
;; : (-> RulePlans AffectedRelations Void)
;; | doc m%
;;     Build invocation-local dependency edges and visit each affected relation
;;     once. Positive, negative and aggregate reads invalidate every rule head.
;;     Marking before enqueue prevents cycles and repeated heads from revisiting.
;;
;;     # Examples
;;
;;     ```scheme
;;     (propagate-affected! [] (vector #t #f))
;;     ;; => no additional affected relations
;;     ```
;;   %
(def (propagate-affected! plans affected)
  (let* ((count (vector-length affected))
         (successors (make-vector count []))
         (pending []))
    (for-each
     (lambda (rule)
       (let (heads (map (lambda (head) (vector-ref head 0)) (vector-ref rule 0)))
         (for-each
          (lambda (clause)
            (when (memq (vector-ref clause 0) '(atom negation aggregate))
              (let (source (vector-ref (vector-ref clause 1) 0))
                (vector-set! successors source
                  (append heads (vector-ref successors source))))))
          (vector-ref rule 1))))
     plans)
    (let seed ((index 0))
      (when (< index count)
        (when (vector-ref affected index) (set! pending (cons index pending)))
        (seed (+ index 1))))
    (let visit ()
      (unless (null? pending)
        (let (source (car pending))
          (set! pending (cdr pending))
          (for-each
           (lambda (target)
             (unless (vector-ref affected target)
               (vector-set! affected target #t)
               (set! pending (cons target pending))))
           (vector-ref successors source)))
        (visit)))))


;; gerbil-ascent-active-prefix
;; : (forall (a) (-> [(Vector a)] [Integer]))
;; : (-> CompiledBody [RelationIndex])
;; | doc m%
;;     Only a pure variable-only atom extends the prunable prefix. Computed
;;     bindings retain the evaluator's complete traversal and cannot be skipped.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-active-prefix [])
;;     ;; => []
;;     ```
;;   %
(def (gerbil-ascent-active-prefix body)
        (if (and (pair? body) (eq? (vector-ref (car body) 0) 'atom))
          (let (atom (vector-ref (car body) 1))
            (cons (vector-ref atom 0)
                  (if (and (null? (vector-ref atom 2))
                           (andmap (lambda (term)
                                     (eq? (car term) 'variable))
                                   (vector-ref atom 1)))
                    (gerbil-ascent-active-prefix (cdr body)) [])))
          []))

;; gerbil-ascent-update-active-plans
;; : (forall (a) (-> (Vector [a]) Vector (Vector [a])))
;; : (-> ActiveStrata AffectedRelations ActiveStrata)
;; | doc m%
;;     A selected rule preserves its immutable plan when every head survives;
;;     partial-head rules receive a new plan and a fresh engine-owned frame.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-update-active-plans '#() '#())
;;     ;; => '#()
;;     ```
;;   %
(def (gerbil-ascent-update-active-plans full-active-by-stratum affected)
(vector-map
                   (lambda (rules)
                     (filter-map
                      (lambda (rule)
                        (let (heads (filter (lambda (head)
                                             (vector-ref affected
                                                         (vector-ref head 0)))
                                           (vector-ref rule 0)))
                          (and (pair? heads)
                               (if (= (length heads) (length (vector-ref rule 0))) rule
                                   (let* ((raw (vector heads (vector-ref rule 1)
                                                       (vector-ref rule 2) (vector-ref rule 3)))
                                          (plan (gerbil-ascent-positive-plan raw)))
                                     (vector heads (vector-ref rule 1) (vector-ref rule 2)
                                             (vector-ref rule 3) (vector-ref rule 4) plan
                                             (and plan (make-vector (vector-ref plan 2) #f)))))))) rules))
                   full-active-by-stratum))
