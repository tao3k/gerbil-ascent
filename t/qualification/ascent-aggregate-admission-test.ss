;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :clan/poo/object .o .cc .ref object-instance)
        (only-in :clan/poo/mop element? validate)
        (only-in :gerbil-ascent/program/objects
                 gerbil-ascent-variable gerbil-ascent-atom gerbil-ascent-aggregate gerbil-ascent-rule)
        (only-in :gerbil-ascent/program/types
                 GerbilAscentTermContract GerbilAscentAtomContract GerbilAscentGuardContract
                 GerbilAscentGeneratorContract GerbilAscentBindingContract
                 GerbilAscentNegationContract GerbilAscentAggregateContract GerbilAscentRuleContract GerbilAscentProgramContract)
        (only-in :gerbil-ascent/t/qualification/ascent-contract-reference-fixture ascent-reference-rule-contract ascent-reference-program-contract))
(export ascent-aggregate-admission-test)

(def (make-mean term)
  (gerbil-ascent-aggregate 'average 'number (list term) '(x) length))
(def (rule-with clause)
  (.cc (gerbil-ascent-rule (list (gerbil-ascent-atom 'out [])) []) 'body (list clause)))
(def (observe call)
  (with-catch (lambda (failure) failure) call))
(def (compare-rule value expected)
  (check-equal? (element? ascent-reference-rule-contract value) expected)
  (check-equal? (element? GerbilAscentRuleContract value) expected))

(def ascent-aggregate-admission-test
  (test-suite "Aggregate admission preserves the ordered public union"
    (test-case "factory aggregates check every field again after direct mutation"
      (let* ((term (gerbil-ascent-variable 'x)) (aggregate (make-mean term))
             (value (rule-with aggregate)))
        (compare-rule value #t)
        (for-each (lambda (slot invalid)
          (let (previous (.ref aggregate slot))
            (try
              (hash-put! (object-instance aggregate) slot invalid)
              (compare-rule value #f)
              (finally (hash-put! (object-instance aggregate) slot previous)))))
          '(ascent-clause-kind variable relation terms variables aggregate checked-operator output-pattern .plan)
          '(wrong #f #f (#f) (1) #f 42 42 #f))
        (let (kind (.ref term 'kind))
          (try
            (hash-put! (object-instance term) 'kind 'wrong)
            (compare-rule value #f)
            (finally (hash-put! (object-instance term) 'kind kind))))
        (compare-rule value #t)))
    (test-case "tuple output and foreign getters retain public admission and exception traces"
      (let* ((x (gerbil-ascent-variable 'x))
             (tuple (gerbil-ascent-aggregate '(a b) 'number (list x) '(x) list (lambda args #t))))
        (compare-rule (rule-with tuple) #t))
      (for-each (lambda (raise?)
        (def (run contract)
          (let (seen [])
            (let* ((clause (.o (:: @ (.ref GerbilAscentAggregateContract 'proto))
                              ascent-clause-kind: 'aggregate
                              (variable (begin (set! seen (cons 'variable seen))
                                (if raise? (raise 'aggregate-getter) 'average)))
                              relation: 'number terms: [] variables: [] aggregate: length
                              output-pattern: #f checked-operator: #f .plan: void))
                   (answer (observe (lambda () (element? contract (rule-with clause))))))
              (list answer (reverse seen)))))
        (check-equal? (run GerbilAscentRuleContract) (run ascent-reference-rule-contract))) '(#f #t)))
    (test-case "every predecessor and aggregate admission hook keeps its original position"
      (let ((value (list (make-mean (gerbil-ascent-variable 'x))))
            (reference (.ref (.ref ascent-reference-rule-contract 'responsibilities) 'body))
            (candidate (.ref (.ref GerbilAscentRuleContract 'responsibilities) 'body)))
        (for-each (lambda (contract)
          (let (admit (.ref contract '.admit))
            (try
              (hash-put! (object-instance contract) '.admit (lambda args (raise 'public-clause-hook)))
              (check-equal? (observe (lambda () (element? reference value))) 'public-clause-hook)
              (check-equal? (observe (lambda () (element? candidate value))) 'public-clause-hook)
              (finally (hash-put! (object-instance contract) '.admit admit)))))
          (list GerbilAscentAtomContract GerbilAscentGuardContract GerbilAscentGeneratorContract
                GerbilAscentBindingContract GerbilAscentNegationContract GerbilAscentAggregateContract))))
    (test-case "owned aggregates retain foreign term getter and exception order"
      (for-each (lambda (raise?)
        (def (run construct)
          (let (seen [])
            (let* ((term (.o (:: @ (.ref GerbilAscentTermContract 'proto))
                             (kind (begin (set! seen (cons 'kind seen)) 'variable))
                             (value (begin (set! seen (cons 'value seen))
                                      (if raise? (raise 'term-getter) 'x)))))
                   (answer (observe (lambda () (construct term) #t))))
              (list answer (reverse seen)))))
        (check-equal?
          (run make-mean)
          (run (lambda (term)
            (validate GerbilAscentAggregateContract
              (.o (:: @ (.ref GerbilAscentAggregateContract 'proto))
                  ascent-clause-kind: 'aggregate variable: 'average relation: 'number
                  terms: (list term) variables: '(x) aggregate: length
                  output-pattern: #f checked-operator: #f .plan: void)))))) '(#f #t)))
    (test-case "changed aggregate slot classifiers remain visible at the body boundary"
      (let* ((value (list (make-mean (gerbil-ascent-variable 'x))))
             (reference (.ref (.ref ascent-reference-rule-contract 'responsibilities) 'body))
             (candidate (.ref (.ref GerbilAscentRuleContract 'responsibilities) 'body))
             (field (.ref (.ref GerbilAscentAggregateContract 'responsibilities) 'variable))
             (classifier (.ref field '.classify)))
        (try
          (hash-put! (object-instance field) '.classify (lambda args (raise 'aggregate-slot-hook)))
          (check-equal? (observe (lambda () (element? reference value))) 'aggregate-slot-hook)
          (check-equal? (observe (lambda () (element? candidate value))) 'aggregate-slot-hook)
          (finally (hash-put! (object-instance field) '.classify classifier)))))
    (test-case "factory Rules with aggregates preserve public rule and predecessor hooks"
      (let* ((aggregate (make-mean (gerbil-ascent-variable 'x)))
             (rule (gerbil-ascent-rule (list (gerbil-ascent-atom 'out [])) (list aggregate)))
             (reference (.ref (.ref ascent-reference-program-contract 'responsibilities) 'rules))
             (candidate (.ref (.ref GerbilAscentProgramContract 'responsibilities) 'rules)))
        (check-equal? (element? reference (list rule)) #t)
        (check-equal? (element? candidate (list rule)) #t)
        (for-each (lambda (contract)
          (let (admit (.ref contract '.admit))
            (try
              (hash-put! (object-instance contract) '.admit (lambda args (raise 'nested-rule-hook)))
              (check-equal? (observe (lambda () (element? reference (list rule)))) 'nested-rule-hook)
              (check-equal? (observe (lambda () (element? candidate (list rule)))) 'nested-rule-hook)
              (finally (hash-put! (object-instance contract) '.admit admit)))))
          (list GerbilAscentAtomContract GerbilAscentGuardContract GerbilAscentGeneratorContract
                GerbilAscentBindingContract GerbilAscentNegationContract GerbilAscentAggregateContract))
        (let (terms (.ref aggregate 'terms))
          (try
            (hash-put! (object-instance aggregate) 'terms '(#f))
            (check-equal? (element? reference (list rule)) #f)
            (check-equal? (element? candidate (list rule)) #f)
            (finally (hash-put! (object-instance aggregate) 'terms terms))))))
    (test-case "nested factory Rules preserve their own public admission override"
      (let* ((aggregate (make-mean (gerbil-ascent-variable 'x)))
             (heads (list (gerbil-ascent-atom 'out [])))
             (rule (gerbil-ascent-rule heads (list aggregate)))
             (candidate (.ref (.ref GerbilAscentProgramContract 'responsibilities) 'rules))
             (admit (.ref GerbilAscentRuleContract '.admit)))
        (try
          (hash-put! (object-instance GerbilAscentRuleContract) '.admit (lambda args (raise 'public-rule-hook)))
          (check-equal? (observe (lambda () (element? GerbilAscentRuleContract rule))) 'public-rule-hook)
          (check-equal? (observe (lambda () (element? candidate (list rule)))) 'public-rule-hook)
          (check-equal? (observe (lambda () (gerbil-ascent-rule heads (list aggregate)))) 'public-rule-hook)
          (finally (hash-put! (object-instance GerbilAscentRuleContract) '.admit admit)))))
    (test-case "constructor normalization and late child-induced obligations remain observable"
      (let* ((term (gerbil-ascent-variable 'x))
             (validator (.ref GerbilAscentAggregateContract '.validate)))
        (try
          (hash-put! (object-instance GerbilAscentAggregateContract) '.validate (lambda (_) 'normalized-aggregate))
          (check-equal? (make-mean term) 'normalized-aggregate)
          (finally (hash-put! (object-instance GerbilAscentAggregateContract) '.validate validator))))
      (let ((term (gerbil-ascent-variable 'x))
            (admit (.ref GerbilAscentTermContract '.admit))
            (obligations (.ref GerbilAscentAggregateContract '.obligations))
            (seen []))
        (def (run construct)
          (set! seen [])
          (hash-put! (object-instance GerbilAscentAggregateContract) '.obligations obligations)
          (let (answer (observe construct)) (list answer (reverse seen))))
        (try
          (hash-put! (object-instance GerbilAscentTermContract) '.admit
            (lambda (candidate context)
              (set! seen (cons 'term-admit seen))
              (let (evidence (admit candidate context))
                (hash-put! (object-instance GerbilAscentAggregateContract) '.obligations
                  (lambda args (set! seen (cons 'aggregate-obligation seen)) (raise 'late-aggregate-obligation)))
                evidence)))
          (check-equal?
            (run (lambda () (make-mean term)))
            (run (lambda ()
              (validate GerbilAscentAggregateContract
                (.o (:: @ (.ref GerbilAscentAggregateContract 'proto))
                    ascent-clause-kind: 'aggregate variable: 'average relation: 'number
                    terms: (list term) variables: '(x) aggregate: length
                    output-pattern: #f checked-operator: #f .plan: void)))))
          (finally
            (hash-put! (object-instance GerbilAscentTermContract) '.admit admit)
            (hash-put! (object-instance GerbilAscentAggregateContract) '.obligations obligations)))))))
