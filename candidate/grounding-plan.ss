;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in "program.ss" candidate-variable?)
        (only-in "funs.ss" candidate-fixed-clause))
(export (struct-out grounding-rule) (struct-out grounding-clause)
        prepare-grounding-rule prepare-grounding-atom prepare-grounding-head prepare-grounding-fixed)

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
    (make-grounding-rule (car head) (prepare-grounding-head head)
      (map (lambda (clause)
             (if (memq (car clause) '(where compute))
               (make-grounding-clause #f (prepare-grounding-fixed clause))
               (make-grounding-clause (car clause) (prepare-grounding-atom clause)))) body)
      label)))

;; prepare-grounding-head
;; : (forall (a) (-> (Atom a) (-> (Bindings a) (Row a))))
;; : (-> InspectedHead HeadRenderer)
;; | doc m%
;;     Resolve an admitted head in term order using invocation-local getters.
;;     Every head variable must be bound by completed body evaluation.
;;
;;     # Examples
;;
;;     ```scheme
;;     ((prepare-grounding-head '(p ?x 7)) '((?x . #f)))
;;     ;; => '(#f 7)
;;     ```
;;   %
(def (prepare-grounding-head head)
    (let (getters (map (lambda (term)
                        (if (candidate-variable? term)
                          (lambda (bindings) (cdr (assq term bindings)))
                          (lambda (_) term))) (cdr head)))
      (lambda (bindings) (map (lambda (get) (get bindings)) getters))))

;; prepare-grounding-fixed
;; : (forall (a) (-> (FixedClause a) (-> (Bindings a) (Maybe (Bindings a)))))
;; : (-> InspectedScalarClause BindingEvaluator)
;; | doc m%
;;     Resolve the admitted scalar operator and operand names once. Each call
;;     checks current binding presence and numeric domains; false values remain
;;     present values. Computation refuses an already bound output.
;;
;;     # Examples
;;
;;     ```scheme
;;     ((prepare-grounding-fixed '(compute ?y (identity ?x))) '((?x . #f)))
;;     ;; => '((?y . #f) (?x . #f))
;;     ```
;;   %
(def (prepare-grounding-fixed clause)
  (match clause
    (['where ['even? name]]
     (lambda (bindings)
       (cond ((assq name bindings)
              => (lambda (input)
                   (and (exact-integer? (cdr input)) (even? (cdr input)) bindings)))
             (else #f))))
    (['where ['< left right]]
     (lambda (bindings)
       (let ((a (assq left bindings)) (b (assq right bindings)))
         (and a b (exact-integer? (cdr a)) (exact-integer? (cdr b))
              (< (cdr a) (cdr b)) bindings))))
    (['compute output ['identity name]]
     (lambda (bindings)
       (let (input (assq name bindings))
         (and input (not (assq output bindings))
              (cons (cons output (cdr input)) bindings)))))
    (['compute output ['+ left right]]
     (lambda (bindings)
       (let ((a (assq left bindings)) (b (assq right bindings)))
         (and a b (not (assq output bindings))
              (exact-integer? (cdr a)) (exact-integer? (cdr b))
              (cons (cons output (+ (cdr a) (cdr b))) bindings)))))
    (else (lambda (bindings) (candidate-fixed-clause clause bindings)))))
