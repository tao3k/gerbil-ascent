;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Rule declarations are Core POO contracts. Relation rows
;;; remain ordinary Scheme values; constructors check their declared arity.
(import (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop define-type element?)
        (only-in :core/types
                 PooFlowNativeObjectContract.
                 poo-flow-predicate-contract)
        (only-in :gerbil-ascent/table/provider
                 GerbilAscentIndexProviderContract)
        (only-in :gerbil-ascent/table/storage
                 GerbilAscentStorageProviderContract))

(export GerbilAscentRelationContract
        GerbilAscentLatticeContract
        GerbilAscentTermContract
        GerbilAscentAtomContract
        GerbilAscentGuardContract
        GerbilAscentGeneratorContract
        GerbilAscentBindingContract
        GerbilAscentNegationContract
        GerbilAscentAggregateContract
        GerbilAscentRuleContract
        GerbilAscentFragmentContract
        GerbilAscentProgramContract
        GerbilAscentSessionContract)

;; : (-> Symbol Procedure PredicateContract)
(def (slot-contract identity predicate)
  (poo-flow-predicate-contract identity predicate
                               (lambda (_value _context) [])))

(def +symbol+ (slot-contract 'ascent/symbol symbol?))
(def +arity+ (slot-contract 'ascent/arity
                           (lambda (value)
                             (and (exact-integer? value) (<= 0 value)))))
(def +fact-budget+
  (slot-contract 'ascent/fact-budget
                 (lambda (value)
                   (and (exact-integer? value) (> value 0)))))
(def +rows+ (slot-contract 'ascent/rows list?))
(def +field-predicates+
  (slot-contract 'ascent/field-predicates
                 (lambda (value)
                   (and (list? value) (andmap procedure? value)))))
(def +provider+
  (slot-contract 'ascent/index-provider
                 (lambda (value)
                   (element? GerbilAscentIndexProviderContract value))))
(def +storage-provider+
  (slot-contract 'ascent/storage-provider
                 (lambda (value)
                   (element? GerbilAscentStorageProviderContract value))))
(def +term-kind+
  (slot-contract 'ascent/term-kind
                 (lambda (value)
                   (memq value '(variable wildcard literal expression pattern)))))
(def +any+ (slot-contract 'ascent/value (lambda (_value) #t)))
(def +plan+ (slot-contract 'ascent/clause-plan procedure?))
;; : (-> Symbol PredicateContract)
(def (clause-kind-contract kind)
  (slot-contract 'ascent/clause-kind (lambda (value) (eq? value kind))))

;;; Relation shape checks arity, source rows, and physical providers before
;;; the evaluator creates any mutable table state.
(define-type (GerbilAscentRelationContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/relation
  proto: (.o)
  responsibilities: (.o name: +symbol+ arity: +arity+ rows: +rows+
                      field-predicates: +field-predicates+
                      storage-kind: (clause-kind-contract 'relation)
                      index-provider: +provider+
                      storage-provider: +storage-provider+))

;;; A lattice owns a join operation; key refinement semantics are distinct
;;; from ordinary set insertion even when source rows have the same shape.
(define-type (GerbilAscentLatticeContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/lattice
  proto: (.o)
  responsibilities: (.o name: +symbol+ arity: +arity+ rows: +rows+
                      field-predicates: +field-predicates+
                      storage-kind: (clause-kind-contract 'lattice)
                      join: (slot-contract 'ascent/lattice-join procedure?)
                      index-provider: +provider+))

;;; Terms retain tagged source intent until planning can resolve variables and
;;; construct executable expression and pattern operations.
(define-type (GerbilAscentTermContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/term
  proto: (.o)
  responsibilities: (.o kind: +term-kind+ value: +any+))

(def +terms+
  (slot-contract 'ascent/terms
                 (lambda (value)
                   (and (list? value)
                        (andmap (lambda (term)
                                  (element? GerbilAscentTermContract term))
                                value)))))

;;; Atom plans bind one relation name to ordered terms and one open planning
;;; slot; the evaluator consumes the lowered plan without row-loop dispatch.
(define-type (GerbilAscentAtomContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/atom
  proto: (.o)
  responsibilities: (.o ascent-clause-kind: (clause-kind-contract 'atom)
                      relation: +symbol+ terms: +terms+ .plan: +plan+))

(def +variables+
  (slot-contract 'ascent/variables
                 (lambda (value)
                   (and (list? value) (andmap symbol? value)))))
(def +generator-output+
  (slot-contract
   'ascent/generator-output
   (lambda (value)
     (or (symbol? value)
         (and (pair? value)
              (list? value)
              (let loop ((remaining value) (seen []))
                (or (null? remaining)
                    (and (symbol? (car remaining))
                         (not (memq (car remaining) seen))
                         (loop (cdr remaining)
                               (cons (car remaining) seen))))))))))
(def +procedure+ (slot-contract 'ascent/procedure procedure?))
(def +optional-procedure+
  (slot-contract 'ascent/optional-procedure
                 (lambda (value) (or (not value) (procedure? value)))))

;;; Guards can inspect only previously bound variables, which the planner
;;; checks before the predicate reaches execution.
(define-type (GerbilAscentGuardContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/guard
  proto: (.o)
  responsibilities: (.o ascent-clause-kind: (clause-kind-contract 'guard)
                      variables: +variables+ predicate: +procedure+
                      .plan: +plan+))

;;; Generators may publish one variable or a tuple; the output descriptor
;;; rejects duplicate names before rows enter the evaluator.
(define-type (GerbilAscentGeneratorContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/generator
  proto: (.o)
  responsibilities: (.o ascent-clause-kind:
                      (clause-kind-contract 'generator)
                      variable: +generator-output+ variables: +variables+
                      generate: +procedure+ .plan: +plan+))

;;; Bindings compute one value from established inputs and introduce exactly
;;; one new variable to subsequent clauses.
(define-type (GerbilAscentBindingContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/binding
  proto: (.o)
  responsibilities: (.o ascent-clause-kind:
                      (clause-kind-contract 'binding)
                      variable: +symbol+ variables: +variables+
                      compute: +procedure+ .plan: +plan+))

;;; Negation is a read of a relation with no new binding; stratification
;;; ensures the referenced rows are stable before the check executes.
(define-type (GerbilAscentNegationContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/negation
  proto: (.o)
  responsibilities: (.o ascent-clause-kind:
                      (clause-kind-contract 'negation)
                      relation: +symbol+ terms: +terms+ .plan: +plan+))

;;; Aggregates consume a relation group and publish one result or a pattern
;;; tuple after the stratum's contributing rows have stabilized.
(define-type (GerbilAscentAggregateContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/aggregate
  proto: (.o)
  responsibilities: (.o ascent-clause-kind:
                      (clause-kind-contract 'aggregate)
                      variable: +generator-output+ relation: +symbol+
                      terms: +terms+ variables: +variables+
                      aggregate: +procedure+
                      output-pattern: +optional-procedure+
                      .plan: +plan+))

(def +clauses+
  (slot-contract 'ascent/clauses
                 (lambda (value)
                   (and (list? value)
                        (andmap (lambda (clause)
                                  (or (element? GerbilAscentAtomContract clause)
                                      (element? GerbilAscentGuardContract clause)
                                      (element? GerbilAscentGeneratorContract clause)
                                      (element? GerbilAscentBindingContract clause)
                                      (element? GerbilAscentNegationContract clause)
                                      (element? GerbilAscentAggregateContract clause)))
                                value)))))
(def +heads+
  (slot-contract 'ascent/heads
                 (lambda (value)
                   (and (pair? value)
                        (list? value)
                        (andmap (lambda (head)
                                  (element? GerbilAscentAtomContract head))
                                value)))))

;;; A rule has at least one head and an ordered body. Shared body bindings
;;; make a multi-head rule one logical derivation event.
(define-type (GerbilAscentRuleContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/rule
  proto: (.o)
  responsibilities: (.o heads: +heads+ body: +clauses+))

(def +relations+
  (slot-contract 'ascent/relations
                 (lambda (value)
                   (and (list? value)
                        (andmap (lambda (relation)
                                  (or (element? GerbilAscentRelationContract relation)
                                      (element? GerbilAscentLatticeContract relation)))
                                value)))))
(def +rules+
  (slot-contract 'ascent/rules
                 (lambda (value)
                   (and (list? value)
                        (andmap (lambda (rule)
                                  (element? GerbilAscentRuleContract rule))
                                value)))))

;;; A fragment publishes an export resolver rather than a mutable mapping.
;;; The constructor copies and checks labels before closing over them.
(def +fragment-exports+
  (slot-contract 'ascent/fragment-exports procedure?))

;;; A fragment carries declarations, rules and instance-local public handles.
;;; It has no execution limits until composition into a bounded program.
(define-type (GerbilAscentFragmentContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/fragment
  proto: (.o)
  responsibilities:
  (.o relations: +relations+ rules: +rules+ exports: +fragment-exports+))

;;; Program budgets bound accepted input, derived facts, and public output
;;; separately; source admission checks them before mutating a session.
(define-type (GerbilAscentProgramContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/program
  proto: (.o)
  responsibilities:
  (.o relations: +relations+
      rules: +rules+
      max-input-facts: +fact-budget+
      max-derived-facts: +fact-budget+
      max-output-facts: +fact-budget+))

;;; Session operations are the only mutable public boundary. A run returns an
;;; immutable result snapshot even when later appends extend the session.
(define-type (GerbilAscentSessionContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/session
  proto: (.o)
  responsibilities:
  (.o .append-source!: +procedure+
      .replace-source!: +procedure+
      .run: +procedure+))
