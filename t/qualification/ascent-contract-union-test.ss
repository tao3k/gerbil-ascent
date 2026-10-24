;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite test-case)
        (only-in :clan/poo/object .o .cc .ref uninstantiate-object!)
        (only-in :clan/poo/mop element? validate)
        (only-in :gerbil-ascent/program/types
                 GerbilAscentAtomContract GerbilAscentGuardContract
                 GerbilAscentRuleContract GerbilAscentProgramContract GerbilAscentSessionContract)
        (only-in :gerbil-ascent/program/objects
                 gerbil-ascent-atom gerbil-ascent-variable
                 gerbil-ascent-guard gerbil-ascent-generator
                 gerbil-ascent-binding gerbil-ascent-negation gerbil-ascent-aggregate
                 gerbil-ascent-relation gerbil-ascent-lattice
                 gerbil-ascent-rule gerbil-ascent-program)
        (only-in :gerbil-ascent/t/qualification/ascent-contract-reference-fixture
                 ascent-reference-rule-contract ascent-reference-program-contract))
(import (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session))
(export ascent-contract-union-test)

(def (same-admission old-contract new-contract value expected)
  (check-equal? (element? old-contract value) expected)
  (check-equal? (element? new-contract value) expected))

(def ascent-contract-union-test
  (test-suite "ASCENT native union classification"
    (test-case "engine and retained Session share native prototype and reject invalid responsibilities"
      (let* ((program (gerbil-ascent-program (list (gerbil-ascent-relation 'input 1 '((1)))) [] 16 16 16))
             (engine (gerbil-ascent-make-engine program #t))
             (session (gerbil-ascent-open-session program))
             (alien (.o .append-source!: void .replace-source!: void .run: void))
             (prototype (.ref GerbilAscentSessionContract 'proto)))
        (uninstantiate-object! GerbilAscentSessionContract)
        (check-equal? (eq? prototype (.ref GerbilAscentSessionContract 'proto)) #t)
        (for-each (lambda (value)
          (check-equal? (eq? (validate GerbilAscentSessionContract value) value) #t)
          (for-each (lambda (slot)
            (check-exception (validate GerbilAscentSessionContract (.cc value slot #f)) true))
            '(.append-source! .replace-source! .run))) (list engine session))
        (check-exception (validate GerbilAscentSessionContract alien) true)))
    (test-case "six clause prototypes retain full responsibility checks"
      (let* ((x (gerbil-ascent-variable 'x))
             (atom (gerbil-ascent-atom 'input (list x)))
             (guard (gerbil-ascent-guard [] (lambda () #t)))
             (generator (gerbil-ascent-generator 'x [] (lambda () '(1))))
             (binding (gerbil-ascent-binding 'x [] (lambda () 1)))
             (negation (gerbil-ascent-negation 'input (list x)))
             (aggregate (gerbil-ascent-aggregate 'total 'input (list x) '(x) length))
             (rule (gerbil-ascent-rule (list atom) []))
             (accepted (list atom guard generator binding negation aggregate))
             (rejected
              (list #f 'atom 1 "atom" [] (.o)
                    (.o ascent-clause-kind: 'atom relation: 'input terms: [])
                    (.cc atom 'ascent-clause-kind 'guard)
                    (.cc atom 'terms '(1))
                    (.cc atom '.plan #f)
                    (.cc guard 'predicate #f)
                    (.cc generator 'variable '(x x))
                    (.cc binding 'variables '(1))
                    (.cc negation 'terms '(#f))
                    (.cc aggregate 'aggregate #f))))
        (for-each
         (lambda (clause)
           (same-admission ascent-reference-rule-contract GerbilAscentRuleContract
                           (.cc rule 'body (list clause)) #t))
         accepted)
        (for-each
         (lambda (clause)
           (same-admission ascent-reference-rule-contract GerbilAscentRuleContract
                           (.cc rule 'body (list clause)) #f))
         rejected)))
    (test-case "overlapping prototypes retain ordered fallback admission"
      (let* ((atom-proto (.ref GerbilAscentAtomContract 'proto))
             (guard-proto (.ref GerbilAscentGuardContract 'proto))
             (clause (.o (:: @ [atom-proto guard-proto])
                         ascent-clause-kind: 'guard relation: 'input terms: []
                         variables: [] predicate: (lambda () #t)
                         checked-operator: #f .plan: (lambda (_plan _bound) #f)))
             (head (gerbil-ascent-atom 'output []))
             (rule (gerbil-ascent-rule (list head) [])))
        (check-equal? (element? GerbilAscentAtomContract clause) #f)
        (check-equal? (element? GerbilAscentGuardContract clause) #t)
        (same-admission ascent-reference-rule-contract GerbilAscentRuleContract
                        (.cc rule 'body (list clause)) #t)))
    (test-case "relation and lattice union rejects malformed responsibilities"
      (let* ((relation (gerbil-ascent-relation 'input 1 '((1))))
             (lattice (gerbil-ascent-lattice 'best 2 '((1 2)) max))
             (program (gerbil-ascent-program [] [] 16 16 64)))
        (for-each
         (lambda (item)
           (same-admission ascent-reference-program-contract GerbilAscentProgramContract
                           (.cc program 'relations (list item)) #t))
         (list relation lattice))
        (for-each
         (lambda (item)
           (same-admission ascent-reference-program-contract GerbilAscentProgramContract
                           (.cc program 'relations (list item)) #f))
         (list #f [] (.o storage-kind: 'relation name: 'input arity: 1 rows: [])
               (.cc relation 'arity -1) (.cc relation 'rows #f)
               (.cc relation 'index-provider #f) (.cc lattice 'join #f)
               (.cc lattice 'storage-kind 'relation)))))))
