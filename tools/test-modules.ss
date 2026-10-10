#!/usr/bin/env gxi
;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Native GxTest owns discovery and assertions. Existing Scheme workgroups and
;;; ASP capacity/profile projection run independent source or compiled modules.
;;; Source directories select the same flat *-test.ss boundary as native GxTest;
;;; GxTest still owns export/Suite/Case discovery and verdicts in each child.
;;; The caller's unchanged deadline covers dispatch, startup and all workers.
(import (only-in :clan/poo/object .cc)
        (only-in :std/string/misc string-contains)
        (only-in :std/string/uuid random-uuid uuid->string)
        (only-in :std/sync/wg make-wg wg-add! wg-wait!)
        (only-in :std/misc/process run-process)
        (only-in :asp-gerbil-scheme/testing-api testing-interface
                 testing-interface-command-for testing-interface-worker-count
                 testing-interface-test-file-batches
                 +testing-memory-profile+ +testing-process-isolation-profile+)
        (only-in :gerbil-ascent/t/native/artifact-admission artifact-directory!))
(export main)
(def (heap-mib heap)
  (let* ((n (string-length heap))
         (unit (and (> n 0) (string-ref heap (- n 1))))
         (value (and (> n 1) (string->number (substring heap 0 (- n 1)))))
         (scale (cond ((eqv? unit #\G) 1024) ((eqv? unit #\M) 1) (else #f))))
    (unless (and scale (exact-integer? value) (> value 0)) (error "expected positive heap in G or M" heap))
    (* value scale)))
(def (module-files paths)
  (apply append
    (map (lambda (path)
      (unless (file-exists? path) (error "missing test module or directory" path))
      (if (eq? (file-type path) 'directory)
        (map (cut string-append path "/" <>)
          (filter (cut string-suffix? "-test.ss" <>) (list-sort string<? (directory-files path))))
        (list path))) paths)))
(def (main mode heap . paths)
  (let* ((files (module-files paths))
         (log-root (string-append ".cache/ascent/test-modules/" (uuid->string (random-uuid)))))
  (unless (member mode '("batched" "isolated")) (error "invalid native testing mode" mode))
  (unless (pair? files) (error "no discovered test modules" paths))
  (artifact-directory! log-root)
  (let* ((profiled (testing-interface profiles:
                    (append (list (.cc +testing-memory-profile+ maxHeapMiB: (heap-mib heap)))
                      (if (string=? mode "isolated") (list +testing-process-isolation-profile+) []))))
         (batches (testing-interface-test-file-batches profiled files))
         (workers (testing-interface-worker-count (length batches)))
         (group (make-wg workers))
         (failures (make-vector (length batches) #f))
         (logs (map (lambda (index)
                      (string-append log-root "/" (number->string index) ".log"))
                    (iota (length batches)))))
    (displayln "TEST-DISPATCH modules=" (length files) " batches=" (length batches) " workers=" workers " mode=" mode " heap=" heap " logs=" log-root) (force-output)
    (for-each
      (lambda (batch log index)
        (wg-add! group
          (lambda ()
            (let (file (car batch))
            ;; Each worker owns one vector slot. Catch its error so the pool
            ;; quiesces and retains every Case log before propagating failure.
            (with-exception-catcher
              (lambda (failure)
                (vector-set! failures index failure)
                (displayln "TEST-BATCH-FAILED " file) (force-output))
              (lambda ()
            (displayln "TEST-BATCH-START " file) (force-output)
            (call-with-output-file log
              (lambda (out)
                ;; The canonical command includes native GxTest's explicit exit
                ;; propagation. Process success is checked after draining output.
                (run-process (append (testing-interface-command-for profiled file '("-v" "5")) (cdr batch))
                  stdout-redirection: #t stderr-redirection: #t
                  coprocess:
                  (lambda (input)
                    (let read-lines ()
                      (let (line (read-line input))
                        (unless (eof-object? line)
                          (display line out) (newline out) (force-output out)
                          ;; Forward actual completed work, not heartbeat ticks.
                          ;; Framework lines remain in the separate Case log.
                          (when (or (string-prefix? "CASE" line) (string-prefix? "MODULE" line)
                                    (string-prefix? "ERROR" line)
                                    (string-prefix? "PROGRESS" line)
                                    (string-contains line "SCOPED-")
                                    (string-contains line "-PAIRS ")
                                    (string-contains line "-COMPLETED ")
                                    (string-contains line " pair="))
                            (displayln "TEST-WORK batch=" file " " line) (force-output))
                          (read-lines))))))))
            (displayln "TEST-BATCH-COMPLETE " file) (force-output))))))) batches logs (iota (length batches)))
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
    (let (failure (find (lambda (value) value) (vector->list failures)))
      (when failure (raise failure)))
    (displayln "TEST-MODULES-OK modules=" (length files)) (displayln "OK"))))
