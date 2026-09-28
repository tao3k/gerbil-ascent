;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :core/observability/debug
                 PooFlowDebugMemoryAnomaly?
                 poo-flow-debug-memory-policy
                 call-with-poo-flow-debug-memory-case-watchdog))

(export ascent-observability-test)

(def ascent-observability-test
  (test-suite "ASCENT Core Observability admission"
    (test-case "the SS watchdog rejects an over-budget operation"
      (let (rejected?
            (with-catch
             PooFlowDebugMemoryAnomaly?
             (lambda ()
               (call-with-poo-flow-debug-memory-case-watchdog
                (poo-flow-debug-memory-policy
                 'ascent-ss-probe
                 heap-limit-bytes: 0
                 live-growth-limit-bytes: 0
                 sample-interval-milliseconds: 1
                 fail-closed?: #t)
                'ascent-ss-probe
                (lambda () 'unexpected-admission)
                max-duration-milliseconds: 1000))))
        (check-equal? rejected? #t)))))
