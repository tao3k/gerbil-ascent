;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :clan/poo/object .o .call .ref)
        (only-in :core/observability/debug
                 poo-flow-debug-memory-snapshot
                 PooFlowDebugMemoryAnomaly?
                 PooFlowDebugDurationAnomaly?)
        (only-in :core/observability/testing-case
                 poo-flow-testing-case-profile?)
        (only-in :gerbil-ascent/t/performance/ascent-ss-profile
                 ascent-ss-profile))

(export ascent-observability-test)

(def ascent-observability-test
  (test-suite "ASCENT Core Observability profile"
    (test-case "a POO slot override rejects an over-budget SS Case"
      (let (rejected-profile
            (.o (:: @ ascent-ss-profile)
                (identity 'ascent-ss-probe)
                (heap-limit-bytes 0)
                (live-growth-limit-bytes 0)
                (sample-interval-milliseconds 1)
                ;; Gambit heap/live fields describe the latest GC. Native cold
                ;; startup can have no such sample yet; request real collection
                ;; instead of relying on interpreted import allocation pressure.
                (collect-before-sample? #t)))
        (let* ((before (poo-flow-debug-memory-snapshot 'zero-budget-before))
               (observed (poo-flow-debug-memory-snapshot
                          'zero-budget-preflight collect?: #t)))
          (displayln "NATIVE-MEMORY-SAMPLE before-heap=" (.ref before 'heap-size-bytes)
                     " collected-heap=" (.ref observed 'heap-size-bytes)
                     " collected-live=" (.ref observed 'live-bytes))
          (force-output)
          (check-equal? (> (.ref observed 'heap-size-bytes) 0) #t))
        (check-equal? (poo-flow-testing-case-profile? rejected-profile) #t)
        (check-equal?
         (with-catch
          PooFlowDebugMemoryAnomaly?
          (lambda ()
            (call-with-values
             (lambda ()
               (.call rejected-profile .run rejected-profile
                      "over-budget ASCENT SS Case"
                      (lambda () 'unexpected-admission)))
             (lambda (value _receipt) value))))
         #t)))
    (test-case "a POO Case slot interrupts a stalled operation"
      (let (bounded-profile
            (.o (:: @ ascent-ss-profile)
                (identity 'ascent/stalled-case-probe)
                ;; Earlier modules may have grown the shared harness heap.
                (heap-limit-bytes 4294967296)
                (live-growth-limit-bytes 4294967296)
                (sample-interval-milliseconds 1)
                (max-duration-milliseconds 25)))
        (check-equal?
         (with-catch
          PooFlowDebugDurationAnomaly?
          (lambda ()
            (.call bounded-profile .run bounded-profile
                   "stalled ASCENT operation"
                   (lambda ()
                     (thread-sleep! 0.1)
                     'unexpected-admission))))
         #t)))))
