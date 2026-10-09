;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Finite operator lowering into rules, with the stable public facade.
;;; Descriptor construction, graph admission and set interpretation have
;;; separate owners; only this invocation emits private relation handles.
(import (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop .defgeneric define-type validate)
        (only-in :core/types PooFlowNativeObjectContract. poo-flow-predicate-contract)
        "operator-descriptor.ss" "operator-measurement.ss" "operator-reference.ss"
        (only-in "operator-lowering.ss" lower-operator-graph)
        (only-in "objects.ss" gerbil-ascent-relation gerbil-ascent-program gerbil-ascent-rule
                 gerbil-ascent-fragment))

(export GerbilAscentOperatorCompilerContract relational-op-compiler
        relational-op-source relational-op-union relational-op-join
        relational-op-select-eq relational-op-project
        relational-op-flatmap relational-op-fix
        relational-op-function relational-op-apply
        relational-op-compile relational-op-fragment
        relational-op-reference relational-op-reference-change
        relational-op-kind relational-op-inputs relational-op-data
        relational-transform? relational-transform-parameter
        relational-transform-body relational-transform-input-arity
        relational-op-measure relational-op-measurement?
        relational-op-measurement-result-values
        relational-op-measurement-join-probes
        relational-op-measurement-fix-body-evaluations
        relational-op-count-join! relational-op-count-fix!
        relational-op? relational-op-arity)

(def +compiler-procedure+
  (poo-flow-predicate-contract 'ascent/operator-compiler-procedure procedure?
                               (lambda (_value _context) [])))

;;; Only behavior lives in the prototype. Each call owns graph admission,
;;; private handles, memo tables and emitted relation/rule declarations.
(define-type (GerbilAscentOperatorCompilerContract
              @ PooFlowNativeObjectContract.)
  identity: 'ascent/operator-compiler
  proto: (.o)
  responsibilities: (.o .make-relation: +compiler-procedure+
                      .make-rule: +compiler-procedure+
                      .make-program: +compiler-procedure+
                      .make-fragment: +compiler-procedure+
                      .compile: +compiler-procedure+
                      .fragment: +compiler-procedure+))

(def OperatorCompiler. (.ref GerbilAscentOperatorCompilerContract 'proto))

(def (check-compiler-budgets! input-limit derived-limit output-limit)
  (unless (and (exact-integer? input-limit) (> input-limit 0)
               (exact-integer? derived-limit) (> derived-limit 0)
               (exact-integer? output-limit) (> output-limit 0))
    (error "operator program budgets must be positive exact integers")))

;;; Generic publication uses the final compiler receiver. Inherited methods
;;; resolve construction stages once, before invocation-owned graph traversal.
;; : (forall (p) (-> OperatorCompiler RelationalOp Nat Nat Nat (Values p Symbol)))
;; : (-> OperatorCompiler RelationalOp InputLimit DerivedLimit OutputLimit (Values Program Symbol))
(.defgeneric (compile-operator compiler root input-limit derived-limit output-limit)
  slot: .compile)
;;; Fragment publication uses the same final receiver with fresh source
;;; handles; the receiver owns export construction rather than the facade.
;; : (forall (f) (-> OperatorCompiler RelationalOp Symbol f))
;; : (-> OperatorCompiler RelationalOp ExportLabel Fragment)
(.defgeneric (fragment-operator compiler root output-label)
  slot: .fragment)

(def relational-op-compiler
  (validate GerbilAscentOperatorCompilerContract
    (.o (:: self OperatorCompiler.)
        (.make-relation gerbil-ascent-relation)
        (.make-rule gerbil-ascent-rule)
        (.make-program gerbil-ascent-program)
        (.make-fragment gerbil-ascent-fragment)
        (.compile
         (let ((make-relation (.ref self '.make-relation))
               (make-rule (.ref self '.make-rule))
               (make-program (.ref self '.make-program)))
           (lambda (root input-limit derived-limit output-limit)
             (check-compiler-budgets! input-limit derived-limit output-limit)
             (let-values (((relations rules sources output _labels)
                           (lower-operator-graph root #f make-relation make-rule)))
               (values (make-program relations rules input-limit derived-limit output-limit sources)
                       output)))))
        (.fragment
         (let ((make-relation (.ref self '.make-relation))
               (make-rule (.ref self '.make-rule))
               (make-fragment (.ref self '.make-fragment)))
           (lambda (root output-label)
             (unless (symbol? output-label)
               (error "operator fragment output label must be a symbol" output-label))
             (let-values (((relations rules sources output labels)
                           (lower-operator-graph root #t make-relation make-rule)))
               (make-fragment relations rules (cons (cons output-label output) labels) sources))))))))

;;; Admit the complete receiver protocol before entering either publication
;;; method; a constructor procedure derives a receiver with the other stages.
;; : (forall (c) (-> c OperatorCompiler))
;; : (-> (Or OperatorCompiler RelationConstructor) OperatorCompiler)
(def (checked-compiler compiler)
  (validate GerbilAscentOperatorCompilerContract
    (if (procedure? compiler)
      (.o (:: @ relational-op-compiler) (.make-relation compiler))
      compiler)))

;; relational-op-compile
;;   : (-> RelationalOp Nat Nat Nat [OperatorCompiler | RelationConstructor] (Values Program Symbol))
;;   | doc m%
;;       Lower a descriptor graph to the same admitted positive-rule
;;       program consumed by the Scheme relational lifecycle.
;;       An optional PO compiler or compiler-owned constructor emits the final relation
;;       representation directly; it is used only during compilation.
;;
;;       # Examples
;;
;;       ```scheme
;;       (relational-op-compile
;;         (relational-op-source 'edge 2 '((1 2))) 8 8 16)
;;       ;; => program and a queryable relation handle
;;       ```
;;     %
;;; The standalone compiler keeps explicit source names for named queries.
;;; The optional owner is a derived compiler or the original constructor API.
(def (relational-op-compile root input-limit derived-limit output-limit
                           (compiler relational-op-compiler))
  (check-compiler-budgets! input-limit derived-limit output-limit)
  (compile-operator (checked-compiler compiler) root input-limit derived-limit output-limit))

;;; A builder graph can participate in the same fragment lifecycle as native
;;; rules. Every named source gets a fresh handle per call; output and source
;;; labels are the only public entry points. Composition supplies budgets.
(def (relational-op-fragment root output-label (compiler relational-op-compiler))
  (unless (symbol? output-label)
    (error "operator fragment output label must be a symbol" output-label))
  (fragment-operator (checked-compiler compiler) root output-label))
