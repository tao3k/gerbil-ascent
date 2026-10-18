;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Union predicates frozen from 74f0046: failed native branches still
;;; construct their rejection receipts. Use the SAME prototype descriptors
;;; as the candidate, so validation differences concern union dispatch only.
(import (only-in :clan/poo/object .cc .ref)
        (only-in :clan/poo/mop element?)
        (only-in :core/types poo-flow-predicate-contract)
        (only-in :gerbil-ascent/program/types
                 GerbilAscentAtomContract GerbilAscentGuardContract
                 GerbilAscentGeneratorContract GerbilAscentBindingContract
                 GerbilAscentNegationContract GerbilAscentAggregateContract
                 GerbilAscentRelationContract GerbilAscentLatticeContract
                 GerbilAscentRuleContract GerbilAscentProgramContract))
(export ascent-reference-rule-contract ascent-reference-program-contract)

(def (slot-contract identity predicate)
  (poo-flow-predicate-contract identity predicate (lambda (_value _context) [])))

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

(def ascent-reference-rule-contract
  (.cc GerbilAscentRuleContract
       'proto (.ref GerbilAscentRuleContract 'proto)
       'responsibilities
       (.cc (.ref GerbilAscentRuleContract 'responsibilities) 'body +clauses+)))

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
                     (element? ascent-reference-rule-contract rule))
                   value)))))

(def ascent-reference-program-contract
  (.cc GerbilAscentProgramContract
       'proto (.ref GerbilAscentProgramContract 'proto)
       'responsibilities
       (.cc (.ref GerbilAscentProgramContract 'responsibilities)
            'relations +relations+ 'rules +rules+)))
