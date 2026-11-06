;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/t/performance/finite-plan/fixture
        :gerbil-ascent/candidate/finite-evidence
        (only-in :gerbil-ascent/candidate/grounding-plan prepare-grounding-fixed)
        (only-in :gerbil-ascent/candidate/funs candidate-fixed-clause))
(export ascent-finite-plan-test)
(def ascent-finite-plan-test
  (test-suite "invocation-owned finite replay plans"
    (test-case "prepared scalar expressions preserve missing false duplicate and exact integer bindings"
      (for-each (lambda (clause)
        (let ((evaluate (prepare-grounding-fixed clause))
              (inputs '(#f 0 1 bad 18446744073709551616)))
          (for-each
           (lambda (a)
             (for-each
              (lambda (b)
                (for-each
                 (lambda (prefix)
                   (let (bindings (append prefix (list (cons '?x a) (cons '?z b))))
                     (check-equal? (evaluate bindings) (candidate-fixed-clause clause bindings))))
                 '(() ((?y . #f)) ((?x . 7)))))
              inputs))
           inputs)
          (check-equal? (evaluate []) (candidate-fixed-clause clause []))))
        '((where (even? ?x)) (where (< ?x ?z)) (compute ?y (identity ?x))
          (compute ?y (+ ?x ?z)))))
    (test-case "complete generated and independently verified models match frozen consumers"
      (for-each (lambda (scenario)
        (let ((old (finite-prepare #t scenario)) (new (finite-prepare #f scenario)))
          (finite-verify! old scenario) (finite-verify! new scenario)
          (check-equal? (finite-consume new scenario) (finite-consume old scenario))
          (displayln "FINITE-CHECKED " scenario) (force-output)))
        '(wide negation reduction small)))
    (test-case "every small scalar negation and reduction work boundary preserves admission"
      (for-each (lambda (scenario)
        (let ((old (finite-prepare #t scenario)) (new (finite-prepare #f scenario)))
          (for-each (lambda (budget)
            (check-equal? (finite-consume new scenario budget) (finite-consume old scenario budget))
            (when (zero? (modulo budget 32))
              (displayln "FINITE-BUDGET-CHECKED " scenario " " budget) (force-output)))
            (append (iota (if (eq? scenario 'small) 64 256) 1) '(504 505 16511 16512 16513)))))
        '(small negation reduction)))
    (test-case "cyclic improper and nested external rows reject before structural hashing"
      (with ([_ snapshot spec rows] (finite-prepare #f 'small))
        (for-each (lambda (malformed)
          (let* ((certificate (candidate-finite-evidence snapshot spec 'program 'complete rows 100000))
                 (closure (finite-evidence-closure certificate)))
            (set-car! (caddr (car closure)) malformed)
            (check-equal? (candidate-verify-finite-evidence snapshot spec 'program 'complete rows certificate 100000)
                          'invalid)))
          (list (let (cycle (list 0)) (set-cdr! cycle cycle) cycle) '(0 . bad) '((0))))))
    (test-case "held verified closure cannot borrow later certificate edits"
      (with ([_ snapshot spec rows] (finite-prepare #f 'small))
        (let (certificate (candidate-finite-evidence snapshot spec 'program 'complete rows 100000))
          (let-values (((verdict closure)
                        (candidate-verified-finite-closure snapshot spec 'program 'complete rows certificate 100000)))
            (check-equal? verdict 'valid)
            (set-car! (car (caddr (car (finite-evidence-closure certificate)))) 999)
            (check-equal? (caddr (car closure)) '((0) (1)))
            (check-equal? (candidate-verify-finite-evidence snapshot spec 'program 'complete rows certificate 100000)
                          'invalid)))))
    (test-case "publication transfers only rows already detached from snapshot input"
      (with ([_ snapshot spec rows] (finite-prepare #f 'small))
        (let ((first (candidate-finite-evidence snapshot spec 'program 'complete rows 100000))
              (second (candidate-finite-evidence snapshot spec 'program 'complete rows 100000)))
          (set-car! (car (caddr (car (finite-evidence-closure first)))) 999)
          (check-equal? (caddr (car (finite-evidence-closure second))) '((0) (1)))
          (let (third (candidate-finite-evidence snapshot spec 'program 'complete rows 100000))
            (check-equal? (finite-evidence-status third) 'complete)
            (check-equal? (caddr (car (finite-evidence-closure third))) '((0) (1)))))))))
