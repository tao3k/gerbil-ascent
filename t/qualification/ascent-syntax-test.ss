;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :clan/poo/object .ref)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :gerbil-ascent/t/qualification/ascent-syntax-fixture
                 ascent-syntax-evaluate ascent-expression-evaluate
                 ascent-index-expression-evaluate)
        (only-in :gerbil-ascent/t/qualification/ascent-index-program-fixture
                 ascent-index-alist-provider)
        (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-evaluate-program
                 gerbil-ascent-expression)
        (only-in :gerbil-ascent/program/funs gerbil-ascent-bind-row))

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
        (check-equal? (not (not (member '(7 7) cross))) #t)))
    (poo-flow-test-case "head expressions require bound inputs"
      (check-exception
       (gerbil-ascent-evaluate-program
        (ascent
         (relation invalid (value))
         (fact (invalid (expr (missing) missing)))
         (bounds 4 4 8)))
       true))
    (poo-flow-test-case "body expression compares after an atom binding"
      (let (term (gerbil-ascent-expression '(x) (lambda (x) (+ x 1))))
        (check-equal?
         (gerbil-ascent-bind-row
          (list (cons 'variable 'x)
                (cons 'expression (.ref term 'value)))
          '(1 2) [])
         '((x . 1)))
        (check-equal?
         (gerbil-ascent-bind-row
          (list (cons 'variable 'x)
                (cons 'expression (.ref term 'value)))
         '(1 3) [])
         #f)))
    (poo-flow-test-case "body expression reads a prior column in one atom"
      (let* ((result
              (ascent-expression-evaluate
               '((1 2) (2 3) (3 5) (8 9))))
             (rows ((.ref result 'rows-of) 'consecutive)))
        (check-equal? (length rows) 3)
        (check-equal? (not (not (member '(1) rows))) #t)
        (check-equal? (not (not (member '(2) rows))) #t)
        (check-equal? (not (not (member '(8) rows))) #t)
        (check-equal? ((.ref result 'rows-of) 'anchored-target)
                      '((9)))))
    (poo-flow-test-case "bound body expression uses the Provider index"
      (let* ((builds [])
             (provider
              (ascent-index-alist-provider
               (lambda (columns) (set! builds (cons columns builds)))))
             (edges
              (let loop ((index 0) (rows '((8 9))))
                (if (= index 32)
                  rows
                  (loop (+ index 1)
                        (cons (list (+ 100 index) (+ 200 index)) rows)))))
             (result (ascent-index-expression-evaluate edges provider)))
        (check-equal? ((.ref result 'rows-of) 'anchored-target) '((9)))
        (check-equal? (not (not (member '(0) builds))) #t)))))
