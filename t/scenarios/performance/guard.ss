;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One bounded process entrypoint for ASCENT SS scenarios. The Core watchdog
;;; samples process-wide counters while the scenario stays on its own thread.
(import (only-in :clan/poo/object .ref)
        (only-in :core/observability/debug
                 PooFlowDebugMemoryAnomaly?
                 PooFlowDebugMemoryAnomaly-receipt
                 PooFlowDebugDurationAnomaly?
                 poo-flow-debug-memory-policy
                 poo-flow-debug-memory-receipt-sexp
                 poo-flow-debug-memory-snapshot
                 call-with-poo-flow-debug-memory-case-watchdog))

(export main)

(def (main . paths)
  (unless (and (= (length paths) 1) (string? (car paths)))
    (error "usage: guard.ss <ASCENT SS scenario>"))
  (let* ((path (car paths))
         (baseline (poo-flow-debug-memory-snapshot 'ascent-ss))
         (policy
          (poo-flow-debug-memory-policy
           'ascent-ss
           heap-limit-bytes:
           (min 805306368 (+ (.ref baseline 'heap-size-bytes) 536870912))
           live-growth-limit-bytes: 268435456
           sample-interval-milliseconds: 25
           fail-closed?: #t)))
    (with-catch
     (lambda (failure)
       (cond
        ((PooFlowDebugMemoryAnomaly? failure)
         (display "[ascent-observability] memory-rejected ")
         (write (poo-flow-debug-memory-receipt-sexp
                 (PooFlowDebugMemoryAnomaly-receipt failure)))
         (newline)
         (force-output)
         (exit 3))
        ((PooFlowDebugDurationAnomaly? failure)
         (displayln "[ascent-observability] duration-rejected")
         (force-output)
         (exit 3))
        (else (raise failure))))
     (lambda ()
       (call-with-values
        (lambda ()
          (call-with-poo-flow-debug-memory-case-watchdog
           policy 'ascent-ss (lambda () (load path))
           max-duration-milliseconds: 175000))
        (lambda (_value _receipt) #!void))))))
