;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Positive-rule declarations are Foundation POO contracts. Relation rows
;;; remain ordinary Scheme values; constructors check their declared arity.
(import (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop define-type element?)
        (only-in :poo-flow-foundation/module-system/types
                 PooFlowNativeObjectContract.
                 poo-flow-predicate-contract))

(export GerbilAscentRelationContract
        GerbilAscentTermContract
        GerbilAscentAtomContract
        GerbilAscentRuleContract
        GerbilAscentProgramContract)

(def (slot-contract identity predicate)
  (poo-flow-predicate-contract identity predicate
                               (lambda (_value _context) [])))

(def +symbol+ (slot-contract 'ascent/symbol symbol?))
(def +arity+ (slot-contract 'ascent/arity
                           (lambda (value)
                             (and (exact-integer? value) (<= 0 value)))))
(def +positive-budget+
  (slot-contract 'ascent/positive-budget
                 (lambda (value)
                   (and (exact-integer? value) (> value 0)))))
(def +rows+ (slot-contract 'ascent/rows list?))
(def +term-kind+
  (slot-contract 'ascent/term-kind
                 (lambda (value) (memq value '(variable literal)))))
(def +any+ (slot-contract 'ascent/value (lambda (_value) #t)))

(define-type (GerbilAscentRelationContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/relation
  proto: (.o)
  responsibilities: (.o name: +symbol+ arity: +arity+ rows: +rows+))

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
  responsibilities: (.o relation: +symbol+ terms: +terms+))

(def +atoms+
  (slot-contract 'ascent/atoms
                 (lambda (value)
                   (and (list? value)
                        (andmap (lambda (atom)
                                  (element? GerbilAscentAtomContract atom))
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
  responsibilities: (.o heads: +heads+ body: +atoms+))

(def +relations+
  (slot-contract 'ascent/relations
                 (lambda (value)
                   (and (list? value)
                        (andmap (lambda (relation)
                                  (element? GerbilAscentRelationContract relation))
                                value)))))
(def +rules+
  (slot-contract 'ascent/rules
                 (lambda (value)
                   (and (list? value)
                        (andmap (lambda (rule)
                                  (element? GerbilAscentRuleContract rule))
                                value)))))

(define-type (GerbilAscentProgramContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/positive-program
  proto: (.o)
  responsibilities:
  (.o relations: +relations+
      rules: +rules+
      max-input-facts: +positive-budget+
      max-derived-facts: +positive-budget+
      max-output-facts: +positive-budget+))
