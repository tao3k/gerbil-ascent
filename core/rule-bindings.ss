;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Runtime operations over admitted terms and evaluation-local environments.
(import (only-in "ordered-call.ss" dispatch-ordered-call))
(export gerbil-ascent-expression-value gerbil-ascent-bind-row gerbil-ascent-head-row
        gerbil-ascent-binding-values gerbil-ascent-call-with-bindings
        gerbil-ascent-extend-pattern)

;;; Admitted input names are proper immutable lists. Resolve all inputs before
;;; invoking user code, preserving left-to-right diagnostics and false values.
;; : (forall (v) (-> Symbol [(Pair Symbol v)] String v))
;; : (-> Name Environment Diagnostic Value)
(def (binding-value name environment diagnostic)
  (let (binding (assq name environment))
    (unless binding (error diagnostic name))
    (cdr binding)))

;; : (forall (v) (-> [Symbol] [(Pair Symbol v)] String [v]))
;; : (-> Names Environment Diagnostic Values)
(def (gerbil-ascent-binding-values names environment diagnostic)
  (map (lambda (name) (binding-value name environment diagnostic)) names))

;;; Direct calls for admitted zero- through four-input callbacks avoid an
;;; argument-list allocation. Larger callbacks keep the same apply protocol.
;; gerbil-ascent-call-with-bindings
;; : (forall (v r) (-> (-> v ... r) [Symbol] [(Pair Symbol v)] String r))
;; : (-> Procedure Names Environment Diagnostic Result)
;; | doc m%
;;     Resolve admitted inputs in order and invoke one callback. Zero through four
;;     inputs use direct calls; larger arities retain the apply convention.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-call-with-bindings + '(x y) '((x . 2) (y . 3)) "missing")
;;     ;; => 5
;;     ```
;;   %
(def (gerbil-ascent-call-with-bindings procedure names environment diagnostic)
  (dispatch-ordered-call (begin) procedure names
    (name (binding-value name environment diagnostic))))

;; : (forall (v r) (-> (Vector Any) [(Pair Symbol v)] r))
;; : (-> ExpressionPayload Environment Value)
(def (gerbil-ascent-expression-value payload environment)
  (gerbil-ascent-call-with-bindings
   (vector-ref payload 1) (vector-ref payload 0) environment
   "unbound ASCENT expression variable"))

;;; Traverse the finite admitted outputs once. This bounds even a cyclic
;;; callback result; only a proper result with exactly the required arity can
;;; extend the environment. Fresh pairs retain output order and the prior tail.
;; gerbil-ascent-extend-pattern
;; : (forall (v) (-> [Symbol] Any [(Pair Symbol v)] String [(Pair Symbol v)]))
;; : (-> Outputs MatchedDatum Environment Diagnostic Environment)
;; | doc m%
;;     Validate a finite output tuple and prepend detached bindings in output
;;     order. The admitted names bound traversal of cyclic callback results.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-extend-pattern '(x) '(#f) '() "invalid")
;;     ;; => ((x . #f))
;;     ```
;;   %
(def (gerbil-ascent-extend-pattern outputs matched environment diagnostic)
  (let extend ((names outputs) (values matched))
    (match* (names values)
      (([] []) environment)
      (([name . remaining] [value . rest])
       (cons (cons name value) (extend remaining rest)))
      (else (error diagnostic matched outputs)))))

;;; Bind one candidate row without mutating the caller's environment. A
;;; repeated variable or failed pattern rejects this candidate with #f.
;; gerbil-ascent-bind-row
;;   : (forall (v) (-> [Term] [v] [(Pair Symbol v)] (Maybe [(Pair Symbol v)])))
;;   : (-> Terms Row Environment (Maybe Environment))
;;   | doc m%
;;       Match ordered terms against one row and return extended bindings.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-bind-row '((variable . x)) '(3) '())
;;       ;; => an environment binding x to 3
;;       ```
;;     %
(def (gerbil-ascent-bind-row terms row environment)
  (let loop ((patterns terms) (values row) (bindings environment))
    (match patterns
      ([] bindings)
      ([term . _]
       (def value (car values))
       (defrule (advance next-bindings)
         (loop (cdr patterns) (cdr values) next-bindings))
       (match term
         (['wildcard . _] (advance bindings))
         (['fresh-variable . name]
          ;; Checked plans prove this name absent, including prior terms.
          (advance (cons (cons name value) bindings)))
         (['pattern . payload]
          ;; Observe outputs after the callback, as in the general protocol.
          (def matched ((vector-ref payload 1) value))
          (def outputs (vector-ref payload 0))
          (and matched
               (advance (gerbil-ascent-extend-pattern
                      outputs matched bindings
                      "ASCENT pattern returned invalid bindings"))))
         (['literal . expected]
          (and (equal? expected value) (advance bindings)))
         (['expression . payload]
          (and (equal? (gerbil-ascent-expression-value payload bindings) value)
               (advance bindings)))
         ([_ . name]
          (cond
            ((assq name bindings) =>
             (lambda (previous)
               (and (equal? (cdr previous) value)
                    (advance bindings))))
            (else (advance (cons (cons name value) bindings))))))))))

;; : (forall (v) (-> [Term] [(Pair Symbol v)] [v]))
;; : (-> Terms Environment Row)
(def (gerbil-ascent-head-row terms environment)
  (map (match <>
         (['literal . value] value)
         (['expression . payload]
          (gerbil-ascent-expression-value payload environment))
         (['pattern . _] (error "ASCENT pattern is invalid in a rule head"))
         (['wildcard . _] (error "ASCENT wildcard is invalid in a rule head"))
         ([_ . name] (binding-value name environment "unbound ASCENT head variable")))
       terms))
