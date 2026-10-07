;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :clan/poo/object .ref)
        :gerbil-ascent/applications/polonius
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session
                 gerbil-ascent-session-run gerbil-ascent-session-replace-source!))
(export ascent-polonius-test)
(def controls
  (call-with-input-file "t/qualification/fixtures/polonius/controls.sexp" read))
(def (check-observations result expected)
  (check-equal? (.ref result 'finished) #t)
  (for-each (lambda (entry)
    (let ((actual ((.ref result 'rows-of) (car entry))) (truth (cdr entry)))
      (unless (= (length actual) (length truth))
        (displayln "POLONIUS-MISMATCH relation=" (car entry) " actual=" actual " expected=" truth))
      (check-equal? (length actual) (length truth))
      (for-each (lambda (row) (check-equal? (and (member row actual) #t) #t)) truth)
      (let (visited [])
        ((.ref result 'visit-rows) (car entry) [] []
          (lambda (row) (set! visited (cons row visited))))
        (check-equal? (length visited) (length truth))
        (for-each (lambda (row) (check-equal? (and (member row visited) #t) #t)) truth)))) expected))
(def ascent-polonius-test
  (test-suite "Complete Polonius Naive application against independent reference outputs"
    (poo-flow-test-case "all thirteen computed observations match ten reference controls in serial and actors"
      (for-each (lambda (control)
        (for-each (lambda (workers)
          (displayln "POLONIUS-CONTROL " (car control) " workers=" workers) (force-output)
          (check-observations
            (gerbil-ascent-evaluate-program (gerbil-ascent-polonius-program (cadr control))
              workers: workers)
            (caddr control))) '(1 2))) controls))
    (poo-flow-test-case "retained cut survives source replacement through initialization and borrow strata"
      (let* ((initial (car controls)) (killed (cadr controls))
             (session (gerbil-ascent-open-session (gerbil-ascent-polonius-program (cadr initial))))
             (held (gerbil-ascent-session-run session)))
        (gerbil-ascent-session-replace-source! session 'loan_killed_at
          (cdr (assq 'loan_killed_at (cadr killed))))
        (check-observations (gerbil-ascent-session-run session) (caddr killed))
        (check-observations held (caddr initial))))
    (poo-flow-test-case "actor cancellation drains before a clean retry of every computed output"
      (let* ((control (car controls)) (program (gerbil-ascent-polonius-program (cadr control)))
             (checks 0))
        (check-exception
          (gerbil-ascent-evaluate-program program workers: 2
            canceled?: (lambda () (set! checks (+ checks 1)) (> checks 3))) true)
        (check-observations (gerbil-ascent-evaluate-program program workers: 2) (caddr control))))
    (poo-flow-test-case "input admission rejects missing duplicate unknown and malformed raw relations"
      (let (inputs (cadar controls))
        (check-exception (gerbil-ascent-polonius-program (cdr inputs)) true)
        (check-exception (gerbil-ascent-polonius-program (cons (cadr inputs) (cdr inputs))) true)
        (check-exception (gerbil-ascent-polonius-program (cons '(unknown) (cdr inputs))) true)
        (check-exception
          (gerbil-ascent-evaluate-program
            (gerbil-ascent-polonius-program (cons '(loan_issued_at ("a" "loan")) (cdr inputs)))) true)))))
