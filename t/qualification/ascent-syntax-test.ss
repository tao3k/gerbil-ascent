;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite)
        (only-in :clan/poo/object .ref)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :gerbil-ascent/t/qualification/ascent-syntax-fixture
                 ascent-syntax-evaluate))

(export ascent-syntax-test)

(def ascent-syntax-test
  (test-suite "ASCENT Scheme source syntax"
    (poo-flow-test-case "lexical literals and multiple fact heads"
      (let* ((result (ascent-syntax-evaluate [] 7))
             (rows-of (.ref result 'rows-of)))
        (check-equal? (rows-of 'seed) '((7)))
        (check-equal? (length (rows-of 'marker)) 2)
        (check-equal? (not (not (member '(7) (rows-of 'marker)))) #t)
        (check-equal? (not (not (member '(8) (rows-of 'marker)))) #t)
        (check-equal? (rows-of 'chosen) '((7)))
        (check-equal? (length (rows-of 'unpacked)) 2)
        (check-equal? (rows-of 'tripled) '((21)))
        (check-equal? (rows-of 'even-packed) '((2)))
        (check-equal? (length (rows-of 'cross)) 6)))
    (poo-flow-test-case "nested disjunction composes finite rule bodies"
      (let* ((result (ascent-syntax-evaluate '((1 2) (2 3) (1 4)) 7))
             (rows-of (.ref result 'rows-of))
             (chosen (rows-of 'chosen))
             (cross (rows-of 'cross)))
        (check-equal? (length chosen) 3)
        (check-equal? (length cross) 6)
        (for-each
         (lambda (row)
           (check-equal? (not (not (member row chosen))) #t))
         '((1) (2) (7)))
        (check-equal? (not (not (member '(2 8) cross))) #t)
        (check-equal? (not (not (member '(7 7) cross))) #t)))))
