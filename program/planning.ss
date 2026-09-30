;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Rule planning is separate from relation state and fixed-point execution.
;;; The passed atom-plan resolves names and arities against one program schema.
(import (only-in "objects.ss" gerbil-ascent-clause-plan)
        (only-in :clan/poo/object .ref))

(export gerbil-ascent-prepare-rule)

;;; A report callback receives the actual failing rule position. The original
;;; exception remains authoritative and is re-raised for direct callers.
;; : (forall (a) (-> (Maybe (-> Path Exception Void)) Path Exception a))
(def (plan-failure callback path failure)
  (when callback (callback path failure))
  (raise failure))

;; : (-> Head (List Symbol) (-> Atom AtomPlan) AtomPlan)
;;; A head may only read variables made available by prior body clauses.
;;; This check shares the same atom-plan as runtime evaluation.
(def (head-plan head bound atom-plan)
  (unless (and (object? head)
               (eq? (.ref head 'ascent-clause-kind) 'atom))
    (error "invalid ASCENT rule head" head))
  (let (plan (atom-plan head))
    (for-each
     (lambda (term)
       (case (car term)
         ((variable)
          (unless (memq (cdr term) bound)
            (error "unsafe ASCENT head variable" (cdr term))))
         ((expression)
          (for-each
           (lambda (name)
             (unless (memq name bound)
               (error "unsafe ASCENT head expression variable" name)))
           (vector-ref (cdr term) 0)))
         ((pattern) (error "ASCENT pattern is invalid in a rule head"))
         ((wildcard) (error "ASCENT wildcard is invalid in a rule head"))))
     (vector-ref plan 1))
    plan))

;;; Body order determines which variables are bound for later clauses.
;;; Only the planner computes this order; diagnostics observe its failures.
;; : (-> Rule Nat (-> Atom AtomPlan) (Maybe PlanErrorCallback) RulePlan)
(def (gerbil-ascent-prepare-rule rule rule-index atom-plan on-plan-error)
  (unless (object? rule)
    (error "invalid ASCENT rule declaration" rule))
  (let* ((body (.ref rule 'body))
         (heads (.ref rule 'heads))
         (bound []) (atoms 0) (body-plans []))
    (unless (and (list? body) (pair? heads) (list? heads))
      (error "invalid ASCENT rule declaration" rule))
    (for-each
     (lambda (clause clause-index)
       (with-catch
        (lambda (failure)
          (plan-failure on-plan-error
                        (list 'rule rule-index 'body clause-index)
                        failure))
        (lambda ()
          (unless (object? clause)
            (error "invalid ASCENT rule clause" clause))
          (let (result
                (gerbil-ascent-clause-plan clause atom-plan bound))
            (set! body-plans (cons (vector-ref result 0) body-plans))
            (set! bound (vector-ref result 1))
            (set! atoms (+ atoms (vector-ref result 2)))))))
     body (iota (length body)))
    (let (planned-heads
          (map
           (lambda (head head-index)
             (with-catch
              (lambda (failure)
                (plan-failure on-plan-error
                              (list 'rule rule-index 'head head-index)
                              failure))
              (lambda () (head-plan head bound atom-plan))))
           heads (iota (length heads))))
      (vector planned-heads (reverse body-plans) atoms rule-index))))
