;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :clan/poo/object .ref)
        (only-in :core/observability/testing-case
                 poo-flow-test-case)
        (only-in :gerbil-ascent/t/qualification/ascent-aggregate-program-fixture
                 ascent-aggregate-fixture-evaluate)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-rule
                 gerbil-ascent-aggregate gerbil-ascent-program
                 gerbil-ascent-evaluate-program gerbil-ascent-count))

(export ascent-aggregate-program-test)

(def (rows result name) ((.ref result 'rows-of) name))

(def ascent-aggregate-program-test
  (test-suite "ASCENT aggregate procedures"
    (poo-flow-test-case "builtins and custom aggregator over source rows"
      (let (result (ascent-aggregate-fixture-evaluate '(1 2 3 4 5)))
        (check-equal? (rows result 'minimum) '((1)))
        (check-equal? (rows result 'maximum) '((5)))
        (check-equal? (rows result 'total) '((15)))
        (check-equal? (rows result 'cardinality) '((5)))
        (check-equal? (length (rows result 'by-group)) 2)
        (check-equal? (not (not (member '(1 30) (rows result 'by-group)))) #t)
        (check-equal? (not (not (member '(2 5) (rows result 'by-group)))) #t)
        (check-equal? (rows result 'average) '((3.0)))
        (check-equal? (length (rows result 'custom)) 2)
        (check-equal? (not (not (member '(1) (rows result 'custom)))) #t)
        (check-equal? (not (not (member '(5) (rows result 'custom)))) #t)))
    (poo-flow-test-case "empty input follows Rust aggregate cardinality"
      (let (result (ascent-aggregate-fixture-evaluate []))
        (check-equal? (rows result 'minimum) [])
        (check-equal? (rows result 'maximum) [])
        (check-equal? (rows result 'average) [])
        (check-equal? (rows result 'total) '((0)))
        (check-equal? (rows result 'cardinality) '((0)))
        (check-equal? (rows result 'custom) [])))
    (poo-flow-test-case "recursive aggregate dependency rejects"
      (check-exception
       (gerbil-ascent-evaluate-program
        (gerbil-ascent-program
         (list (gerbil-ascent-relation 'number 1 []))
         (list (gerbil-ascent-rule
                (list (gerbil-ascent-atom
                       'number (list (gerbil-ascent-variable 'value))))
                (list (gerbil-ascent-aggregate
                       'value 'number (list (gerbil-ascent-variable 'x))
                       [] gerbil-ascent-count))))
         8 8 8)) true))))
