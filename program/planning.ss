;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Rule planning is separate from relation state and fixed-point execution.
;;; The passed atom-plan resolves names and arities against one program schema.
(import (only-in "objects.ss" gerbil-ascent-clause-plan
                 gerbil-ascent-bound-membership)
        (only-in "funs.ss" gerbil-ascent-rule-strata
                 gerbil-ascent-delta-positions)
        (only-in "positive.ss" gerbil-ascent-prepare-rule-activations)
        (only-in :clan/poo/object .ref))

(export gerbil-ascent-prepare-rule gerbil-ascent-prepare-program)

;;; Compile declarations against one validated schema without reading source
;;; rows or allocating storage state, indexes, variable frames or timers.
;;; The result retains declarations; its vector layout is shared with the cache
;;; and engine.
;; : (-> Relations Rules ProgramSchema (Maybe PlanErrorCallback) Analysis)
(def (gerbil-ascent-prepare-program relations rules schema on-plan-error)
  (let* ((names (vector-ref schema 1))
         (arity (vector-ref schema 2))
         (positions (vector-ref schema 4))
         (kinds (vector-ref schema 8))
         (count (vector-length names)))
    (def position-of
      (if (= count 1)
        (lambda (name)
          (if (eq? name (vector-ref names 0))
            0
            (error "unknown ASCENT relation" name)))
        (lambda (name)
          (let (slot (hash-get positions name))
            (unless slot (error "unknown ASCENT relation" name))
            (- slot 1)))))
    (def (atom-plan atom)
      (unless (and (object? atom)
                   (memq (.ref atom 'ascent-clause-kind)
                         '(atom negation aggregate)))
        (error "invalid ASCENT atom declaration" atom))
      (let* ((index (position-of (.ref atom 'relation)))
             (terms (.ref atom 'terms)))
        (unless (and (list? terms) (= (length terms) (vector-ref arity index)))
          (error "ASCENT atom arity mismatch" (.ref atom 'relation)))
        (vector index
                (map (lambda (term)
                       (let (kind (.ref term 'kind))
                         (unless (memq kind '(variable wildcard literal expression pattern))
                           (error "invalid ASCENT rule term" kind))
                         (cons kind (.ref term 'value))))
                     terms))))
    (let* ((plans
            (map (lambda (rule index)
                   (gerbil-ascent-prepare-rule
                    rule index atom-plan on-plan-error))
                 rules (iota (length rules))))
           (strata
            (with-catch
             (lambda (failure)
               (plan-failure on-plan-error '(program dependencies) failure))
             (lambda () (gerbil-ascent-rule-strata plans count kinds)))))
      (let (active (active-rules plans strata))
        (vector relations rules plans strata active
                (gerbil-ascent-prepare-rule-activations active))))))

;;; Group each rule's heads once instead of rescanning every rule in every
;;; stratum. Reverse both accumulators to retain head and source-rule order.
;; : (-> RulePlans Strata ActiveRulesByStratum)
(def (active-rules plans strata)
  (let* ((highest (if (zero? (vector-length strata)) -1
                     (apply max (vector->list strata))))
         (active (make-vector (+ highest 1) [])))
    (for-each
     (lambda (rule)
       (let (heads-by-stratum (make-hash-table-eqv))
         (for-each
          (lambda (head)
            (hash-update! heads-by-stratum
                          (vector-ref strata (vector-ref head 0))
                          (cut cons head <>) []))
          (vector-ref rule 0))
         (hash-for-each
          (lambda (stratum heads)
            (vector-set! active stratum
              (cons (vector (reverse heads) (vector-ref rule 1)
                            (gerbil-ascent-delta-positions
                             (vector-ref rule 1) strata stratum)
                            (vector-ref rule 3))
                    (vector-ref active stratum))))
          heads-by-stratum)))
     plans)
    (vector-map reverse active)))

;;; A report callback receives the actual failing rule position. The original
;;; exception remains authoritative and is re-raised for direct callers.
;; : (forall (a) (-> (Maybe (-> Path Exception Void)) Path Exception a))
(def (plan-failure callback path failure)
  (when callback (callback path failure))
  (raise failure))

;; : (-> Head (-> Symbol Boolean) (-> Atom AtomPlan) AtomPlan)
;;; A head may only read variables made available by prior body clauses.
;;; Heads and body clauses resolve against the same validated schema.
(def (head-plan head bound? atom-plan)
  (unless (and (object? head)
               (eq? (.ref head 'ascent-clause-kind) 'atom))
    (error "invalid ASCENT rule head" head))
  (let (plan (atom-plan head))
    (for-each
     (lambda (term)
       (case (car term)
         ((variable)
          (unless (bound? (cdr term))
            (error "unsafe ASCENT head variable" (cdr term))))
         ((expression)
          (for-each
           (lambda (name)
             (unless (bound? name)
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
    (let* ((bound? (gerbil-ascent-bound-membership bound))
           (planned-heads
            (map
             (lambda (head head-index)
               (with-catch
                (lambda (failure)
                  (plan-failure on-plan-error
                                (list 'rule rule-index 'head head-index) failure))
                (lambda () (head-plan head bound? atom-plan))))
             heads (iota (length heads)))))
      (vector planned-heads (reverse body-plans) atoms rule-index))))
