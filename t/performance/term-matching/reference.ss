;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Runtime operations over admitted terms and evaluation-local environments.
(import (only-in :gerbil-ascent/core/ordered-call dispatch-ordered-call))
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
    (if (null? names)
      (if (null? values) environment (error diagnostic matched outputs))
      (if (pair? values)
        (cons (cons (car names) (car values))
              (extend (cdr names) (cdr values)))
        (error diagnostic matched outputs)))))

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
    (if (null? patterns)
      bindings
      (let* ((term (car patterns))
             (value (car values))
             (kind (car term)))
        (case kind
          ((wildcard)
           (loop (cdr patterns) (cdr values) bindings))
          ((fresh-variable)
           ;; Private checked plans prove this name absent, including earlier
           ;; terms in the same atom. No row-time environment search is needed.
           (loop (cdr patterns) (cdr values)
                 (cons (cons (cdr term) value) bindings)))
          ((pattern)
           (let* ((payload (cdr term))
                  (matched ((vector-ref payload 1) value))
                  (outputs (vector-ref payload 0)))
             (and matched
                  (loop (cdr patterns) (cdr values)
                        (gerbil-ascent-extend-pattern
                         outputs matched bindings
                         "ASCENT pattern returned invalid bindings")))))
          ((literal expression)
           (and (equal? (if (eq? kind 'literal)
                          (cdr term)
                          (gerbil-ascent-expression-value
                           (cdr term) bindings))
                        value)
                (loop (cdr patterns) (cdr values) bindings)))
          (else
           (let* ((name (cdr term))
                  (previous (assq name bindings)))
             (if previous
               (and (equal? (cdr previous) value)
                    (loop (cdr patterns) (cdr values) bindings))
               (loop (cdr patterns) (cdr values)
                     (cons (cons name value) bindings))))))))))

;; : (forall (v) (-> [Term] [(Pair Symbol v)] [v]))
;; : (-> Terms Environment Row)
(def (gerbil-ascent-head-row terms environment)
  (map (lambda (term)
         (case (car term)
           ((literal) (cdr term))
           ((expression)
            (gerbil-ascent-expression-value (cdr term) environment))
           ((pattern)
            (error "ASCENT pattern is invalid in a rule head"))
           ((wildcard)
            (error "ASCENT wildcard is invalid in a rule head"))
           (else
            (let (binding (assq (cdr term) environment))
              (unless binding
                (error "unbound ASCENT head variable" (cdr term)))
              (cdr binding)))))
       terms))
