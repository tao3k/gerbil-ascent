;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/iter for iter Iterator &Iterator-next!)
        (only-in :gerbil-ascent/core/relation-view
                 gerbil-ascent-for-each-row gerbil-ascent-any-row?)
        (only-in :gerbil-ascent/core/rule-bindings gerbil-ascent-bind-row
                 gerbil-ascent-binding-values gerbil-ascent-call-with-bindings
                 gerbil-ascent-extend-pattern))
(export make-rule-body-visitor)

;; make-rule-body-visitor
;; : (forall (a e r) (-> (-> a e Boolean Any r) (-> List Integer Integer e (-> e Any) Any)))
;; : (-> CallbackRows RuleBodyVisitor)
;; | doc m%
;;     Bind an engine's row reader to the ordered host-clause traversal.
;;     Only positive atoms advance the delta-pivot depth. Negation and aggregates
;;     read complete tables; callbacks retain source order and exception order.
;;     No rows, membership, budgets or scheduling state belong to this module.
;;
;;     # Examples
;;
;;     ```scheme
;;     ((make-rule-body-visitor rows) '() -1 0 '() values)
;;     ;; => '(); the empty body consumes its unchanged environment once
;;     ```
;;   %
(def (make-rule-body-visitor callback-rows)
  (def (visit-body body delta-at depth environment consume)
    (if (null? body)
      (consume environment)
      (let (clause (car body))
        (cond
         ((eq? (vector-ref clause 0) 'atom)
          (let* ((atom (vector-ref clause 1))
                 (rows (callback-rows atom environment
                                     (= depth delta-at) #f)))
            (gerbil-ascent-for-each-row
             (lambda (row)
               (let (bound (gerbil-ascent-bind-row (vector-ref atom 3)
                                      row environment))
                 (when bound
                   (visit-body (cdr body) delta-at (+ depth 1)
                               bound consume))))
             rows)))
         ((eq? (vector-ref clause 0) 'negation)
          (let* ((atom (vector-ref clause 1))
                 (rows (callback-rows atom environment #f #f)))
            (unless (gerbil-ascent-any-row?
                     (lambda (row)
                       (gerbil-ascent-bind-row (vector-ref atom 3)
                                 row environment))
                     rows)
              (visit-body (cdr body) delta-at depth
                          environment consume))))
         ((eq? (vector-ref clause 0) 'aggregate)
          (let* ((atom (vector-ref clause 1))
                 (rows (callback-rows atom environment #f #f))
                 (variables (vector-ref clause 3))
                 (tuples []))
            (gerbil-ascent-for-each-row
             (lambda (row)
               (let (bound (gerbil-ascent-bind-row (vector-ref atom 3)
                                      row environment))
                 (when bound
                   (set! tuples
                     (cons (gerbil-ascent-binding-values
                            variables bound "unbound ASCENT clause variable")
                           tuples)))))
             rows)
            (let (values ((vector-ref clause 4)
                          (reverse tuples)))
              (unless (list? values)
                (error "ASCENT aggregator must return a list"
                       values))
              (for-each
               (lambda (value)
                 (let* ((output (vector-ref clause 2))
                        (matcher (vector-ref clause 5))
                        (next-environment
                         (if matcher
                           (let (matched (matcher value))
                             (gerbil-ascent-extend-pattern
                              output matched environment
                              "ASCENT aggregate pattern returned invalid bindings"))
                           (cons (cons output value)
                                 environment))))
                   (visit-body (cdr body) delta-at depth
                               next-environment consume)))
               values))))
         ((eq? (vector-ref clause 0) 'guard)
          (let (pass? (gerbil-ascent-call-with-bindings
                        (vector-ref clause 2) (vector-ref clause 1)
                        environment "unbound ASCENT clause variable"))
            (unless (boolean? pass?)
              (error "ASCENT guard must return a boolean" pass?))
            (when pass?
              (visit-body (cdr body) delta-at depth
                          environment consume))))
         ((eq? (vector-ref clause 0) 'generator)
          (let (values (gerbil-ascent-call-with-bindings
                        (vector-ref clause 3) (vector-ref clause 2)
                        environment "unbound ASCENT clause variable"))
            (for (value values)
              (let* ((output (vector-ref clause 1))
                     (next-environment
                      (if (list? output)
                        (let (row (if (vector? value)
                                     (vector->list value)
                                     value))
                          (unless (and (list? row)
                                       (= (length row)
                                          (length output)))
                            (error "ASCENT generator tuple arity mismatch"
                                   value))
                          (gerbil-ascent-bind-row output row
                                                  environment))
                        (cons (cons output value) environment))))
                (visit-body (cdr body) delta-at depth
                            next-environment consume)))))
         ((eq? (vector-ref clause 0) 'binding)
          (let (value (gerbil-ascent-call-with-bindings
                        (vector-ref clause 3) (vector-ref clause 2)
                        environment "unbound ASCENT clause variable"))
            (visit-body (cdr body) delta-at depth
                        (cons (cons (vector-ref clause 1) value)
                              environment)
                        consume)))))))
  visit-body)
