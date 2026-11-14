;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/t/performance/paired-study
        :gerbil-ascent/t/performance/uf-membership/fixture)
(export main run-membership-control)
(def (run-membership-control scenario receipt-path control)
  ;; Diagnostic controls use the same workload, limits and rejecting gate.
  ;; A deliberately slower arm must fail; identities must not regress merely
  ;; because they occupy a different position in the shared VM heap.
  (def (arm old?)
    (cond ((equal? control "same-reference") #t)
          ((member control '("same-current" "slower-current")) #f)
          ((equal? control "reversed") (not old?))
          (else (error "unknown membership control" control))))
  (run-paired-scenario (call-with-input-file "t/performance/uf-membership/benchmark.ss" read)
    (lambda (old? input) (ui-prepare (arm old?) input))
    (lambda (state input old?)
      (when (and (not old?) (equal? control "slower-current"))
        ;; Scalar work preserves the allocation control. Its checksum keeps
        ;; the deliberate CPU regression observable without changing answers.
        (unless (= (let loop ((n 1000000) (sum 0))
                     (if (zero? n) sum (loop (- n 1) (+ sum n))))
                   500000500000)
          (error "invalid slowdown checksum")))
      (ui-consume state input (arm old?)))
    (lambda (_state input) (ui-expected (ui-prepare #t input) input))
    scenario receipt-path))
(def (main scenario receipt-path (control "comparison"))
  (if (equal? control "comparison")
    (run-paired-study (call-with-input-file "t/performance/uf-membership/benchmark.ss" read)
      ui-prepare ui-consume ui-expected scenario receipt-path)
    (begin (run-membership-control scenario receipt-path control) (exit 0))))
