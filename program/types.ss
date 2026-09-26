;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Rule declarations are Foundation POO contracts. Relation rows
;;; remain ordinary Scheme values; constructors check their declared arity.
(import (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop define-type element?)
        (only-in :poo-flow-foundation/module-system/types
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
        GerbilAscentProgramContract)

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
                 (lambda (value) (memq value '(variable literal)))))
(def +any+ (slot-contract 'ascent/value (lambda (_value) #t)))
(def +plan+ (slot-contract 'ascent/clause-plan procedure?))
(def (clause-kind-contract kind)
  (slot-contract 'ascent/clause-kind (lambda (value) (eq? value kind))))

(define-type (GerbilAscentRelationContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/relation
  proto: (.o)
  responsibilities: (.o name: +symbol+ arity: +arity+ rows: +rows+
                      storage-kind: (clause-kind-contract 'relation)
                      index-provider: +provider+
                      storage-provider: +storage-provider+))

(define-type (GerbilAscentLatticeContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/lattice
  proto: (.o)
  responsibilities: (.o name: +symbol+ arity: +arity+ rows: +rows+
                      storage-kind: (clause-kind-contract 'lattice)
                      join: (slot-contract 'ascent/lattice-join procedure?)
                      index-provider: +provider+))

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

(define-type (GerbilAscentAtomContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/atom
  proto: (.o)
  responsibilities: (.o ascent-clause-kind: (clause-kind-contract 'atom)
                      relation: +symbol+ terms: +terms+ .plan: +plan+))

(def +variables+
  (slot-contract 'ascent/variables
                 (lambda (value)
                   (and (list? value) (andmap symbol? value)))))
(def +procedure+ (slot-contract 'ascent/procedure procedure?))

(define-type (GerbilAscentGuardContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/guard
  proto: (.o)
  responsibilities: (.o ascent-clause-kind: (clause-kind-contract 'guard)
                      variables: +variables+ predicate: +procedure+
                      .plan: +plan+))

(define-type (GerbilAscentGeneratorContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/generator
  proto: (.o)
  responsibilities: (.o ascent-clause-kind:
                      (clause-kind-contract 'generator)
                      variable: +symbol+ variables: +variables+
                      generate: +procedure+ .plan: +plan+))

(define-type (GerbilAscentBindingContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/binding
  proto: (.o)
  responsibilities: (.o ascent-clause-kind:
                      (clause-kind-contract 'binding)
                      variable: +symbol+ variables: +variables+
                      compute: +procedure+ .plan: +plan+))

(define-type (GerbilAscentNegationContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/negation
  proto: (.o)
  responsibilities: (.o ascent-clause-kind:
                      (clause-kind-contract 'negation)
                      relation: +symbol+ terms: +terms+ .plan: +plan+))

(define-type (GerbilAscentAggregateContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/aggregate
  proto: (.o)
  responsibilities: (.o ascent-clause-kind:
                      (clause-kind-contract 'aggregate)
                      variable: +symbol+ relation: +symbol+
                      terms: +terms+ variables: +variables+
                      aggregate: +procedure+ .plan: +plan+))

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

(define-type (GerbilAscentProgramContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/program
  proto: (.o)
  responsibilities:
  (.o relations: +relations+
      rules: +rules+
      max-input-facts: +fact-budget+
      max-derived-facts: +fact-budget+
      max-output-facts: +fact-budget+))
