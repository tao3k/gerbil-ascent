;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :clan/poo/object .ref)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :gerbil-ascent/t/qualification/ascent-syntax-fixture
                 ascent-syntax-evaluate ascent-expression-evaluate
                 ascent-index-expression-evaluate
                 ascent-pattern-clauses-evaluate)
        (only-in :gerbil-ascent/t/qualification/ascent-index-program-fixture
                 ascent-index-alist-provider)
        (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-evaluate-program
                 gerbil-ascent-expression
                 gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-run)
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
        (check-equal? (not (not (member '(0) builds))) #t)))
    (poo-flow-test-case "inline pattern binds later columns in one atom"
      (let* ((result
              (gerbil-ascent-evaluate-program
               (ascent
                (relation optional-pair (value next)
                          '(((some . 4) 5) ((some . 4) 6)
                            (#f 5)))
                (relation matched (value))
                ((matched x) <--
                 (optional-pair (pat (x) (cons 'some x))
                                (expr (x) (+ x 1))))
                (bounds 8 8 16))))
             (rows ((.ref result 'rows-of) 'matched)))
        (check-equal? rows '((4)))))
    (poo-flow-test-case "inline pattern rejects duplicate bindings"
      (check-exception
       (gerbil-ascent-evaluate-program
        (ascent
         (relation item (value) '((1)))
         (relation out (value))
         ((out x) <-- (item x) (item (pat (x) x)))
         (bounds 4 4 8)))
       true))
    (poo-flow-test-case "inline pattern cannot bind in rule head"
      (check-exception
       (gerbil-ascent-evaluate-program
        (ascent
         (relation out (value))
         (fact (out (pat (x) x)))
         (bounds 4 4 8)))
       true))
    (poo-flow-test-case "let and for destructure native Gerbil values"
      (let* ((result (ascent-pattern-clauses-evaluate '((1 2) (3 4))))
             (rows-of (.ref result 'rows-of)))
        (check-equal? (length (rows-of 'let-pair)) 2)
        (check-equal? (not (not (member '(1 3) (rows-of 'let-pair)))) #t)
        (check-equal? (not (not (member '(3 5) (rows-of 'let-pair)))) #t)
        (check-equal? (length (rows-of 'for-pair)) 4)
        (check-equal? (not (not (member '(2 1) (rows-of 'for-pair)))) #t)))
    (poo-flow-test-case "typed relation checks source and derived fields"
      (check-equal?
       ((.ref
         (gerbil-ascent-evaluate-program
          (ascent
           (relation mixed ((value integer?) tag) '((2 "ok")))
           (bounds 4 4 8)))
         'rows-of) 'mixed)
       '((2 "ok")))
      (check-equal?
       ((.ref
         (gerbil-ascent-evaluate-program
          (ascent
           (relation input ((value integer?)) '((2)))
           (relation output ((value integer?)))
           ((output (expr (x) (+ x 1))) <-- (input x))
           (bounds 4 4 8)))
         'rows-of) 'output)
       '((3)))
      (check-exception
       (ascent
        (relation input ((value integer?)) '(("bad")))
        (bounds 4 4 8))
       true)
      (check-exception
       (gerbil-ascent-evaluate-program
        (ascent
         (relation input ((value integer?)) '((2)))
         (relation output ((value integer?)))
         ((output (lit "bad")) <-- (input x))
         (bounds 4 4 8)))
       true))
    (poo-flow-test-case "typed session update rejects before mutation"
      (let* ((session
              (gerbil-ascent-open-session
               (ascent
                (relation input ((value integer?)) '((1)))
                (relation output ((value integer?)))
                ((output x) <-- (input x))
                (bounds 4 4 8))))
             (first (gerbil-ascent-session-run session)))
        (check-equal? ((.ref first 'rows-of) 'output) '((1)))
        (check-exception
         (gerbil-ascent-session-append-source! session 'input '("bad"))
         true)
        (gerbil-ascent-session-append-source! session 'input '(2))
        (check-equal?
         ((.ref (gerbil-ascent-session-run session) 'rows-of) 'output)
         '((1) (2)))))))
