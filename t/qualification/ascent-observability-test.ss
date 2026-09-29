;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :clan/poo/object .o .call)
        (only-in :core/observability/debug
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
                (sample-interval-milliseconds 1)))
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
