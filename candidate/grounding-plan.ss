;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in "program.ss" candidate-variable?)
        (only-in "funs.ss" candidate-fixed-clause))
(export (struct-out grounding-rule) (struct-out grounding-clause)
        prepare-grounding-rule prepare-grounding-atom)

;; : (-> Symbol HeadRenderer GroundingClauses Label GroundingRule)
(defstruct grounding-rule (name head body label) final: #t)
;; : (-> (Maybe Symbol) ClauseEvaluator GroundingClause)
(defstruct grounding-clause (relation apply) final: #t)

;; prepare-grounding-atom
;; : (forall (a) (-> (Atom a) (-> (Row a) (Bindings a) (Maybe (Bindings a)))))
;; : (-> InspectedAtom RowMatcher)
;; | doc m%
;;     Classify each inspected term once per invocation. Matching borrows rows
;;     and extends ordered bindings without changing prior pairs. Repeated
;;     variables still compare against the first binding, including false values.
;;
;;     # Examples
;;
;;     ```scheme
;;     ((prepare-grounding-atom '(edge ?x ?x)) '(2 2) [])
;;     ;; => ((?x . 2))
;;     ```
;;   %
(def (prepare-grounding-atom atom)
  (foldr
   (lambda (term next)
     (cond
      ((eq? term '?_) (lambda (row bindings) (next (cdr row) bindings)))
      ((candidate-variable? term)
       (lambda (row bindings)
         (cond ((assq term bindings)
                => (lambda (old)
                     (and (equal? (cdr old) (car row)) (next (cdr row) bindings))))
               (else (next (cdr row) (cons (cons term (car row)) bindings))))))
      (else (lambda (row bindings)
              (and (equal? term (car row)) (next (cdr row) bindings))))))
   (lambda (_ bindings) bindings) (cdr atom)))

;; prepare-grounding-rule
;; : (forall (a) (-> (InspectedRule a) (GroundingRule a)))
;; : (-> InspectedRule GroundingRule)
;; | doc m%
;;     Prepare the head and ordered body before any grounding probes. Plans
;;     belong to one synchronous replay, carry no rows or mutable bindings,
;;     and preserve scalar evaluation and rule occurrence labels.
;;
;;     # Examples
;;
;;     ```scheme
;;     (prepare-grounding-rule (vector '(p ?x) '((s ?x)) 7))
;;     ;; => private head renderer and ordered clause evaluators
;;     ```
;;   %
(def (prepare-grounding-rule rule)
  (with (#(head body label) rule)
    (let (getters (map (lambda (term)
                        (if (candidate-variable? term)
                          (lambda (bindings) (cdr (assq term bindings)))
                          (lambda (_) term))) (cdr head)))
      (make-grounding-rule (car head)
        (lambda (bindings) (map (lambda (get) (get bindings)) getters))
        (map (lambda (clause)
               (if (memq (car clause) '(where compute))
                 (make-grounding-clause #f (lambda (bindings) (candidate-fixed-clause clause bindings)))
                 (make-grounding-clause (car clause) (prepare-grounding-atom clause)))) body)
        label))))
