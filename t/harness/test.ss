#!/usr/bin/env gxi
;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Scheme GxTest owns discovery and assertions. Existing Scheme workgroups and
;;; ASP capacity/profile projection run independent source or compiled modules.
;;; Source directories select the same flat *-test.ss boundary as compiled GxTest;
;;; GxTest still owns export/Suite/Case discovery and verdicts in each child.
;;; The caller's unchanged deadline covers dispatch, startup and all workers.
(import (only-in :clan/poo/object .cc)
        (only-in :std/list/list partition group-n-consecutive)
        (only-in :std/string/misc string-contains)
        (only-in :std/string/uuid random-uuid uuid->string)
        (only-in :std/sync/wg make-wg wg-add! wg-wait!)
        (only-in :std/misc/process run-process)
        (only-in :asp-gerbil-scheme/testing-api testing-interface
                 testing-interface-command-for testing-interface-worker-count
                 testing-interface-test-file-batches testing-interface-test-file-isolated?
                 testing-interface-map-profile testing-test-selector
                 +testing-memory-profile+ +testing-process-isolation-profile+)
        (only-in :gerbil-ascent/t/harness/artifact-admission artifact-directory!)
        (only-in :gerbil-ascent/bindings/artifact artifact-development-program)
        (only-in :gerbil-ascent/build-modules gerbil-ascent-build-input-modules))
(export main source-live-ratio source-vm-command striped-module-files source-test-interface source-test-batches single-thread-vm-command preparation-batches-bounded?)
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
(def (striped-module-files files workers)
  ;; Scheme batching takes contiguous, balanced slices. Transpose the ordered
  ;; inventory first so neighboring expensive UF/reference modules occupy
  ;; different workers; compiled profiles and capacity still own the batches.
  (let (lanes (make-vector workers []))
    (for-each (lambda (file index)
      (let (lane (modulo index workers))
        (vector-set! lanes lane (cons file (vector-ref lanes lane)))))
      files (iota (length files)))
    (apply append (map reverse (vector->list lanes)))))

;; Exhaustive corpora own independent processes. Darwin overlaps them with
;; the final ordinary wave to avoid both a long exhaustive tail and sustained
;; exhaustive/ordinary allocation contention. Other hosts keep their native
;; order. Capacity, isolation, module coverage and runtime options are equal.
(def (source-test-interface mode heap)
  (foldl (lambda (name testing)
    (testing-interface-map-profile testing
      (testing-test-selector 'contains name)
      +testing-process-isolation-profile+))
   (testing-interface profiles:
     (append (list (.cc +testing-memory-profile+ maxHeapMiB: (heap-mib heap)))
       (if (string=? mode "isolated") (list +testing-process-isolation-profile+) [])))
   '("ascent-semi-naive-test." "ascent-candidate-flow-test.")))
;; Native GxTest prepares all modules before running a batch. Refine compatible
;; batches to release those contexts on VM exit without lowering concurrency.
;; BEGIN GENERATED PREPARATION GROUPS
(def (preparation-refined-batches profiled compatible)
  (if (null? compatible) []
    (let* ((workers (testing-interface-worker-count (length compatible)))
           (width (preparation-batch-width (preparation-batch-width (length compatible) workers) workers)))
      (apply append
        (map (cut group-n-consecutive width <>)
          (testing-interface-test-file-batches profiled
            (striped-module-files compatible workers)))))))
(def (preparation-batch-width entries workers)
  (if (zero? entries) 0 (+ 1 (quotient (- entries 1) workers))))
(def (preparation-batches-bounded? batches entries workers)
  (let (bound (preparation-batch-width (preparation-batch-width entries workers) workers))
    (andmap (lambda (batch) (<= (length batch) bound)) batches)))
(def (single-thread-vm-command command (live-ratio #f))
  (let wrap ((arguments command))
    (cond
      ((null? arguments) (error "native test command has no expression" command))
      ((equal? (car arguments) "-e")
       (cons "-e" (cons
         (string-append
           "(let (n (##current-vm-processor-count)) (unless (= n 1) (error \"expected one processor per test VM\" n)) (displayln \"VM-RUNTIME processors=\" n)) "
           "(let (ratio (##get-live-percent)) "
           (if live-ratio
             (string-append "(unless (= ratio " (number->string live-ratio)
               ") (error \"unexpected test VM live ratio\" ratio)) ") "")
           "(displayln \"VM-GC-RUNTIME live-ratio=\" ratio)) "
           (cadr arguments))
         (cddr arguments))))
      (else (cons (car arguments) (wrap (cdr arguments)))))))
(def (source-test-batches profiled files mode
                          (defer? (cond-expand (darwin #t) (else #f))))
  (let (batches
    (if (string=? mode "batched")
      (let-values (((isolated compatible)
                    (partition (lambda (file) (testing-interface-test-file-isolated? profiled file)) files)))
        (let* ((ordinary (preparation-refined-batches profiled compatible))
               (prefix-count (max 0 (- (length ordinary) (testing-interface-worker-count (length files))))))
          (if defer? (append (take ordinary prefix-count) (map list isolated) (drop ordinary prefix-count))
                     (append (map list isolated) ordinary))))
      (testing-interface-test-file-batches profiled files)))
    (unless (or (null? files)
                (preparation-batches-bounded? batches (length files)
                  (testing-interface-worker-count (length files))))
      (error "source batch retains too many entry modules"))
    batches))
;;; Use the SDK's soft GC target only for memory-sensitive ordinary Darwin
;;; batches. Isolated exhaustive declaration work keeps the default target.
(def (source-live-ratio profiled file (darwin? (cond-expand (darwin #t) (else #f))))
  (if (and darwin? (not (testing-interface-test-file-isolated? profiled file))) 80 50))
(def (source-vm-command command program (live-ratio #f))
  ;; Keep upstream GxTest, argv, heap options and its original explicit exit.
  ;; The package's admitted linked shell owns only the preloaded production
  ;; closure; Suite carriers are still expanded from source in each fresh VM.
  (unless (or (not live-ratio) (memv live-ratio '(50 80)))
    (error "unsupported source VM live ratio" live-ratio))
  (when (and live-ratio
             (not (ormap (cut string-prefix? "-:max-heap=" <>) command)))
    (error "native test command has no heap limit" command))
  (let (command
         (single-thread-vm-command
          (if live-ratio
            (map (lambda (argument)
                   (if (string-prefix? "-:max-heap=" argument)
                     (string-append argument ",live-ratio=" (number->string live-ratio))
                     argument)) command)
            command)
          live-ratio))
    (if program
      (cons program
        (let replace ((arguments (cdr command)))
          (cond
            ((null? arguments) (error "native test command has no expression" command))
            ((equal? (car arguments) "-e") (cons "--eval-plain" (cdr arguments)))
            (else (cons (car arguments) (replace (cdr arguments)))))))
      command)))

;; END GENERATED PREPARATION GROUPS

(def (main mode heap . paths)
  (let* ((files (module-files paths))
         (program (artifact-development-program (current-directory) gerbil-ascent-build-input-modules))
         (log-root (string-append ".cache/ascent/test-modules/" (uuid->string (random-uuid)))))
  (unless (member mode '("batched" "isolated")) (error "invalid compiled testing mode" mode))
  (unless (pair? files) (error "no discovered test modules" paths))
  (artifact-directory! log-root)
  (let* ((profiled (source-test-interface mode heap))
         (batches (source-test-batches profiled files mode))
         (workers (testing-interface-worker-count (length batches)))
         (group (make-wg workers))
         (failures (make-vector (length batches) #f))
         (logs (map (lambda (index)
                      (string-append log-root "/" (number->string index) ".log"))
                    (iota (length batches)))))
    (displayln "TEST-VM-DRIVER linked=" (if program 1 0)) (force-output)
    (displayln "TEST-DISPATCH modules=" (length files) " batches=" (length batches) " workers=" workers " max-batch-modules=" (apply max (map length batches)) " mode=" mode " heap=" heap " logs=" log-root) (force-output)
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
                ;; The canonical command includes compiled GxTest's explicit exit
                ;; propagation. Process success is checked after draining output.
                (run-process (append (source-vm-command (testing-interface-command-for profiled file '("-v" "5")) program
                                    (source-live-ratio profiled file)) (cdr batch))
                  stdout-redirection: #t stderr-redirection: #t
                  coprocess:
                  (lambda (input)
                    (let read-lines ((error-detail? #f))
                      (let (line (read-line input))
                        (unless (eof-object? line)
                          (display line out) (newline out) (force-output out)
                          ;; Forward actual completed work, not heartbeat ticks.
                          ;; Framework lines remain in the separate Case log.
                          (when (or error-detail? (string-prefix? "CASE" line) (string-prefix? "MODULE" line)
                                    (string-prefix? "ERROR" line)
                                    (string-prefix? "VM-GC-RUNTIME " line)
                                    ;; GxTest emits the exception immediately after
                                    ;; its ERROR context. Preserve the typed cause
                                    ;; even if another batch exhausts the deadline.
                                    (string-prefix? "*** ERROR" line)
                                    (string-prefix? "--- " line)
                                    (string-prefix? "... " line)
                                    (string-prefix? "HARNESS-OK " line)
                                    (string=? "OK" line)
                                    (string-prefix? "PROGRESS" line)
                                    (string-contains line "SCOPED-")
                                    (string-contains line "-PAIRS ")
                                    (string-contains line "-COMPLETED ")
                                    (string-contains line " pair="))
                            (displayln "TEST-WORK batch=" file " " line) (force-output))
                          (read-lines (string-prefix? "ERROR " line)))))))))
            (displayln "TEST-BATCH-COMPLETE " file) (force-output))))))) batches logs (iota (length batches)))
    (try (wg-wait! group)
      ;; Keep compiled framework logs contiguous, so the existing Case audit
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
