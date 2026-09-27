;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :clan/poo/object .ref)
        (only-in :core/observability/testing-case
                 poo-flow-test-case)
        (only-in :gerbil-ascent/t/qualification/ascent-aggregate-program-fixture
                 ascent-aggregate-fixture-evaluate
                 ascent-aggregate-pattern-evaluate
                 ascent-derived-aggregate-fixture-evaluate)
        (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-relation gerbil-ascent-variable
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
    (poo-flow-test-case "aggregate result destructures a native pattern"
      (check-equal?
       (rows (ascent-aggregate-pattern-evaluate '(5 2 5 1))
             'extrema-pair)
       '((1 5)))
      (check-equal?
       (rows (ascent-aggregate-pattern-evaluate []) 'extrema-pair)
       []))
    (poo-flow-test-case "aggregate output pattern rejects a mismatched value"
      (check-exception
       (gerbil-ascent-evaluate-program
        (ascent
         (relation number (value) '((1)))
         (relation out (first second))
         ((out first second) <--
          (aggregate (first second)
                     (lambda (_tuples) (list (vector 1)))
                     () (number value)
                     (vector first second)))
         (bounds 4 4 8)))
       true))
    (poo-flow-test-case "aggregate a completed recursive closure in a higher stratum"
      (let (result (ascent-derived-aggregate-fixture-evaluate
                   '((0 1) (1 2) (2 0)) '(0 1 2 5)))
        (check-equal? (length (rows result 'path)) 9)
        (check-equal? (length (rows result 'reach-count)) 4)
        (for-each
         (lambda (row)
           (check-equal? (not (not (member row (rows result 'reach-count))))
                         #t))
         '((0 3) (1 3) (2 3) (5 0)))))
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
