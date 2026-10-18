;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import "grounding-plan.ss"
        (only-in :gerbil-ascent/candidate/reduction-plan prepare-reduction-row)
        (only-in :gerbil-ascent/candidate/program candidate-variable?)
        (only-in "funs.ss" candidate-required-entry))
(export (struct-out finite-rule) (struct-out finite-clause) prepare-finite-rule)
;; : (-> ReplayRelation HeadRenderer FiniteClauses Nat FiniteRule)
(defstruct finite-rule (relation head body level) final: #t)
;; : (-> ClauseKind (Maybe ReplayRelation) ClauseEvaluator (Maybe Symbol) Operator RowValue FiniteClause)
(defstruct finite-clause (kind relation apply output operator value) final: #t)

;; prepare-finite-rule
;; : (forall (r a) (-> (InspectedRule a) (-> Symbol r) Levels (FiniteRule r a)))
;; : (-> InspectedRule RelationResolver Strata FiniteRule)
;; | doc m%
;;     Resolve ordered rule metadata against one replay's private relations.
;;     Matching expressions retain no row/frontier; execution admits every
;;     probe before consulting them. Negation and reduction preserve clause order.
;;
;;     # Examples
;;
;;     ```scheme
;;     (prepare-finite-rule rule resolve-relation levels)
;;     ;; => one invocation-owned rule plan, with no evaluated body rows
;;     ```
;;   %
(def (prepare-finite-rule rule resolve levels)
  (with (#(head body _) rule)
    (let (known (make-hash-table-eq size: (length body)))
      (make-finite-rule (resolve (car head)) (prepare-grounding-head head)
        (map (lambda (clause)
               (case (car clause)
                 ((where compute)
                  (when (eq? (car clause) 'compute) (hash-put! known (cadr clause) #t))
                  (make-finite-clause 'fixed #f
                    (prepare-grounding-fixed clause) #f #f #f))
                 ((not)
                  (let (atom (cadr clause))
                    (make-finite-clause 'not (resolve (car atom))
                      (prepare-grounding-atom atom) #f #f #f)))
                 ((reduce)
                  (let (atom (cadddr clause))
                    (let-values (((match-row value) (prepare-reduction-row atom (caddr clause) known)))
                      (hash-put! known (cadr clause) #t)
                      (make-finite-clause 'reduce (resolve (car atom))
                        match-row (cadr clause) (caddr clause) value))))
                 (else
                  (for-each (lambda (term)
                              (when (and (candidate-variable? term) (not (eq? term '?_)))
                                (hash-put! known term #t))) (cdr clause))
                  (make-finite-clause 'atom (resolve (car clause))
                         (prepare-grounding-atom clause) #f #f #f)))) body)
        (cdr (candidate-required-entry (car head) levels))))))
