#!/usr/bin/env gxi
;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Native GxTest owns discovery and assertions. Existing Scheme workgroups and
;;; ASP capacity/profile projection run independent compiled Suites in bounded
;;; processes. Each process counterbalances its own pairs sequentially. The
;;; enclosing 120-second deadline covers all workers, including child startup.
(import (only-in :clan/poo/object .cc)
        (only-in :std/string/misc string-contains)
        (only-in :std/sync/wg make-wg wg-add! wg-wait!)
        (only-in :std/misc/process run-process)
        (only-in :asp-gerbil-scheme/testing-api testing-interface
                 testing-interface-command-for testing-interface-worker-count
                 +testing-memory-profile+ +testing-process-isolation-profile+)
        (only-in :gerbil-ascent/t/native/artifact-admission artifact-directory!))
(export main)
(def (main . files)
  (unless (pair? files) (error "performance contracts require explicit compiled modules"))
  (for-each (lambda (file)
              (unless (file-exists? file) (error "missing compiled performance module" file))) files)
  (artifact-directory! ".cache/ascent/performance-contracts")
  (let* ((profiled (testing-interface profiles:
                    (list (.cc +testing-memory-profile+ maxHeapMiB: 2048)
                          +testing-process-isolation-profile+)))
         (workers (testing-interface-worker-count (length files)))
         (group (make-wg workers))
         (logs (map (lambda (index)
                      (string-append ".cache/ascent/performance-contracts/" (number->string index) ".log"))
                    (iota (length files)))))
    (displayln "PERFORMANCE-DISPATCH modules=" (length files) " workers=" workers) (force-output)
    (for-each
      (lambda (file log)
        (wg-add! group
          (lambda ()
            (displayln "PERFORMANCE-MODULE-START " file) (force-output)
            (call-with-output-file log
              (lambda (out)
                ;; The canonical command includes native GxTest's explicit exit
                ;; propagation. Process success is checked after draining output.
                (run-process (testing-interface-command-for profiled file '("-v" "5"))
                  stdout-redirection: #t stderr-redirection: #t
                  coprocess:
                  (lambda (input)
                    (let read-lines ()
                      (let (line (read-line input))
                        (unless (eof-object? line)
                          (display line out) (newline out) (force-output out)
                          ;; Forward actual completed work, not heartbeat ticks.
                          ;; Framework lines remain in the separate Case log.
                          (when (or (string-contains line "-PAIRS ")
                                    (string-contains line "-COMPLETED ")
                                    (string-contains line " pair="))
                            (displayln "PERFORMANCE-WORK " file " " line) (force-output))
                          (read-lines))))))))
            (displayln "PERFORMANCE-MODULE-COMPLETE " file) (force-output)))) files logs)
    (try (wg-wait! group)
      ;; Keep native framework logs contiguous, so the existing Case audit
      ;; cannot misattribute interleaved MODULE/CASE lines from different workers.
      (finally
        (for-each (lambda (log)
                    (when (file-exists? log)
                      (call-with-input-file log
                        (lambda (input)
                          (let read-lines ()
                            (let (line (read-line input))
                              (unless (eof-object? line) (displayln line) (read-lines)))))))) logs)))
    (displayln "PERFORMANCE-CONTRACTS-OK modules=" (length files)) (displayln "OK")))
