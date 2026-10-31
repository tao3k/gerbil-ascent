;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/t/performance/uf-plan/fixture
        (only-in :std/error Error-message)
        (only-in :std/string/uuid random-uuid uuid->string)
        (only-in :gerbil-ascent/t/performance/uf-membership/runner run-membership-control)
        (only-in :gerbil-ascent/t/performance/paired-study run-paired-scenario)
        (only-in :asp-gerbil-scheme/benchmark-api benchmark-fixture-contract-pass?))
(export ascent-uf-plan-performance-test)
(def ascent-uf-plan-performance-test
  (test-suite "Frozen UF query plan measurement admission"
    (test-case "calibration checks intermediate batches even when the final batch agrees"
      (check-equal?
        (with-catch Error-message
          (lambda ()
            (run-paired-scenario
              (call-with-input-file "t/performance/uf-membership/benchmark.ss" read)
              (lambda (_old? _input) (vector 0))
              (lambda (state _input _old?)
                (let (n (+ 1 (vector-ref state 0)))
                  (vector-set! state 0 n)
                  (if (= n 9) -1 0)))
              (lambda (_state _input) 0) "export" ".cache/ascent/rejected-calibration.ss")
            #f))
        "PAIRED-STUDY execution lifecycle differs"))
    (test-case "export identities pass and equal-allocation CPU regression is rejected"
      (def (receipt-path mode)
        (path-expand (string-append ".cache/ascent/export-" mode "-"
                                   (uuid->string (random-uuid)) ".ss")))
      (for-each (lambda (mode)
        (let (path (receipt-path mode))
          (run-membership-control "export" path mode)
          (let (receipt (call-with-input-file path read))
            (check-equal? (cdr (assq 'passed? receipt)) #t)
            (check-equal? (cdr (assq 'old-bytes receipt)) (cdr (assq 'new-bytes receipt))))))
        '("same-current" "same-reference" "reversed"))
      (let* ((path (receipt-path "slower-current"))
             (failure (with-catch Error-message
                        (lambda () (run-membership-control "export" path "slower-current") #f)))
             (receipt (call-with-input-file path read)))
        (check-equal? failure "PAIRED-STUDY execution gate failed")
        (check-equal? (cdr (assq 'passed? receipt)) #f)
        (check-equal? (cdr (assq 'old-bytes receipt)) (cdr (assq 'new-bytes receipt)))
        (check (> (cdr (assq 'new-cpu-us receipt))
                  (+ (* 11/10 (cdr (assq 'old-cpu-us receipt))) 20)) => #t)))
    (test-case "fixed paired fixture admits the unchanged resource gates"
      (check (benchmark-fixture-contract-pass?
               (call-with-input-file "t/performance/uf-plan/benchmark.ss" read)) => #t))
    (test-case "current-baseline initialization gates remain independently fixed"
      (check (benchmark-fixture-contract-pass?
               (call-with-input-file "t/performance/uf-initialization/benchmark.ss" read)) => #t))
    (test-case "compact query targets and full-row controls are independently admitted"
      (check (benchmark-fixture-contract-pass?
               (call-with-input-file "t/performance/uf-compact-query/benchmark.ss" read)) => #t))
    (test-case "streamed admission uses a current baseline and unchanged query controls"
      (check (benchmark-fixture-contract-pass?
               (call-with-input-file "t/performance/uf-selector-init/benchmark.ss" read)) => #t))
    (test-case "owner construction retains fixed capture and lifecycle gates"
      (check (benchmark-fixture-contract-pass?
               (call-with-input-file "t/performance/uf-owner-plans/benchmark.ss" read)) => #t))
    (test-case "bounded allocation covers every key and propagates rejected legs"
      (for-each (lambda (old?)
        (let ((prepared (ui-prepare old? 'small)) (calls 0))
          ;; Nonuniform answers detect lost or duplicated slice boundaries.
          (set-car! (cddr prepared) '((0 3 2) (99 3 2) (0 3 2) (99 3 2) (0 3 2)))
          (let-values (((result bytes)
                        (ui-allocate prepared 'small old?
                          (lambda (call) (set! calls (+ calls 1)) (values (call) 2)) 2)))
            (check-equal? result (ui-consume prepared 'small old?))
            (check-equal? result 3)
            (check-equal? calls 3)
            (check-equal? bytes 6))
          (check-exception
            (ui-allocate prepared 'small old? (lambda (_call) (error "rejected leg")) 2)
            exception?))) '(#t #f)))
    (test-case "allocation segment admission rejects nonpositive and inexact sizes"
      (let (prepared (ui-prepare #f 'small))
        (for-each (lambda (size)
                    (check-exception (ui-allocate prepared 'small #f void size) exception?))
          '(0 -1 1/2 #f))))))
