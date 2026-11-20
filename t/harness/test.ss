#!/usr/bin/env gxi
;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Scheme GxTest owns discovery and assertions. Existing Scheme workgroups and
;;; ASP capacity/profile projection run independent source or compiled modules.
;;; Source directories select the same flat *-test.ss boundary as compiled GxTest;
;;; GxTest still owns export/Suite/Case discovery and verdicts in each child.
;;; The caller supervises dispatch, startup and progress across all workers.
(import (only-in :clan/poo/object .cc)
        (only-in :gerbil/runtime/thread with-lock)
        (only-in :std/list/list partition group-n-consecutive)
        (only-in :std/string/misc string-contains)
        (only-in :std/string/uuid random-uuid uuid->string)
        (only-in :std/sync/wg make-wg wg-add! wg-wait!)
        (only-in :std/misc/process run-process)
        (only-in :asp-gerbil-scheme/testing-api testing-interface
                 testing-interface-command-for testing-interface-worker-count
                 testing-interface-test-file-batches testing-interface-test-file-isolated? testing-interface-test-file-serial?
                 testing-interface-map-profile testing-test-selector
                 +testing-memory-profile+ +testing-process-isolation-profile+ +testing-serial-resource-profile+)
        (only-in :gerbil-ascent/t/harness/artifact-admission artifact-directory!))
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

;; Exhaustive, process-wide Contract mutation and source-build Suites own VMs.
;; Use the framework's balanced compatible batches without a second partition.
;; BEGIN GENERATED PREPARATION GROUPS
(def (source-test-interface mode heap)
  (let (isolated
         (foldl
           (lambda (name testing)
             (testing-interface-map-profile testing
               (testing-test-selector 'contains name)
               +testing-process-isolation-profile+))
           (testing-interface
             profiles:
             (append (list (.cc +testing-memory-profile+ maxHeapMiB: (heap-mib heap)))
               (if (string=? mode "isolated") (list +testing-process-isolation-profile+) [])))
           '("ascent-semi-naive-test."
             "ascent-candidate-flow-test."
             "ascent-aggregate-admission-test."
             "ascent-delta-admission-test."
             "ascent-operator-publication-test."
             "ascent-value-membership-test."
             "scheme-closure-contract-test."
             "static-link-inputs-test."
             "yuanxu-library-test.")))
    (foldl
      (lambda (name testing)
        (testing-interface-map-profile testing
          (testing-test-selector 'contains name)
          +testing-serial-resource-profile+))
      isolated
      '("static-link-inputs-test."
        "yuanxu-library-test."))))
(def (preparation-compatible-batches profiled compatible darwin?)
  (if (null? compatible) []
    (let (native
           (testing-interface-test-file-batches profiled
             (striped-module-files compatible
               (testing-interface-worker-count (length compatible)))))
      (if darwin?
        (apply append (map (cut group-n-consecutive 8 <>) native))
        native))))
(def (preparation-batch-width entries workers (darwin? (cond-expand (darwin #t) (else #f))))
  (let (width (if (zero? entries) 0 (+ 1 (quotient (- entries 1) workers))))
    (if darwin? (min 8 width) width)))
(def (preparation-batches-bounded? batches entries workers (darwin? (cond-expand (darwin #t) (else #f))))
  (let (bound (preparation-batch-width entries workers darwin?))
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
(def (source-test-batches profiled files mode (darwin? (cond-expand (darwin #t) (else #f))))
  (let (batches
         (if (string=? mode "batched")
           (let-values (((isolated compatible)
                         (partition (lambda (file)
                                      (testing-interface-test-file-isolated? profiled file)) files)))
             (append (map list isolated)
                     (preparation-compatible-batches profiled compatible darwin?)))
           (testing-interface-test-file-batches profiled files)))
    (unless (or (null? files)
                (preparation-batches-bounded? batches (length files)
                  (testing-interface-worker-count (length files)) darwin?))
      (error "source batch retains too many entry modules"))
    batches))
;;; Parallel source expansion shares the host memory. Serial build projections
;;; and compiled isolated profiles keep the released collector's default target.
(def (source-live-ratio (darwin? (cond-expand (darwin #t) (else #f)))
                        parallel-source?: (parallel-source? #t))
  (if (and darwin? parallel-source?) 90 50))
(def (source-vm-command command (live-ratio #f))
  ;; Keep upstream GxTest, argv, heap options and its original explicit exit.
  (unless (or (not live-ratio) (memv live-ratio '(50 90)))
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
    command))

;; END GENERATED PREPARATION GROUPS

(def (main mode heap . paths)
  (let* ((files (module-files paths))
         (log-root (string-append ".cache/ascent/test-modules/" (uuid->string (random-uuid)))))
    (unless (member mode '("batched" "isolated"))
      (error "invalid compiled testing mode" mode))
    (unless (pair? files) (error "no discovered test modules" paths))
    (artifact-directory! log-root)
    (let* ((profiled (source-test-interface mode heap))
           (batches (source-test-batches profiled files mode))
           (workers (testing-interface-worker-count (length batches)))
           (group (make-wg workers))
           (failures (make-vector (length batches) #f))
           (serial-work [])
           (output-lock (make-mutex 'source-test-output))
           (logs (map (lambda (index)
                        (string-append log-root "/" (number->string index) ".log"))
                      (iota (length batches)))))
      (def (emit . arguments)
        (with-lock output-lock
          (lambda ()
            (apply displayln arguments)
            (force-output))))
      (def (run-batch! batch log index)
        (let (file (car batch))
          (with-exception-catcher
            (lambda (failure)
              (vector-set! failures index (list failure))
              (emit "TEST-BATCH-FAILED " file))
            (lambda ()
              (emit "TEST-BATCH-START " file)
              (call-with-output-file log
                (lambda (out)
                  (run-process
                    (append
                      (source-vm-command
                        (testing-interface-command-for profiled file '("-v" "5"))
                        (source-live-ratio
                          parallel-source?:
                          (and (string=? mode "batched")
                               (not (testing-interface-test-file-serial? profiled file)))))
                      (cdr batch))
                    stdout-redirection: #t stderr-redirection: #t
                    coprocess:
                    (lambda (input)
                      (let read-lines ((error-detail? #f))
                        (let (line (read-line input))
                          (unless (eof-object? line)
                            (display line out) (newline out) (force-output out)
                            ;; Forward real work; retain contiguous native logs.
                            (when (or error-detail?
                                      (string-prefix? "CASE" line)
                                      (string-prefix? "MODULE" line)
                                      (string-prefix? "ERROR" line)
                                      (string-prefix? "VM-GC-RUNTIME " line)
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
                              (emit "TEST-WORK batch=" file " " line))
                            (read-lines (string-prefix? "ERROR " line)))))))))))
          (emit "TEST-BATCH-COMPLETE " file)))
      (displayln "TEST-DISPATCH modules=" (length files)
                 " batches=" (length batches) " workers=" workers
                 " max-batch-modules=" (apply max (map length batches))
                 " mode=" mode " heap=" heap " logs=" log-root)
      (force-output)
      (for-each
        ;; BEGIN GENERATED SOURCE QUEUE ADMISSION
        (lambda (batch log index)
          (let (work (lambda () (run-batch! batch log index)))
            (if (testing-interface-test-file-serial? profiled (car batch))
              (set! serial-work (cons work serial-work))
              (wg-add! group work))))
        ;; END GENERATED SOURCE QUEUE ADMISSION
        batches logs (iota (length batches)))
      (try
        ;; BEGIN GENERATED SOURCE PHASE BARRIER
        (begin
          (wg-wait! group)
          (emit "TEST-SERIAL-BARRIER pending=" (length serial-work))
          (for-each (lambda (work) (work)) (reverse serial-work)))
        ;; END GENERATED SOURCE PHASE BARRIER
        (finally
          (for-each
            (lambda (log)
              (when (file-exists? log)
                (call-with-input-file log
                  (lambda (input)
                    (let read-lines ()
                      (let (line (read-line input))
                        (unless (eof-object? line)
                          (displayln line)
                          (read-lines))))))))
            logs)))
      (let (failure (find pair? (vector->list failures)))
        (when failure (raise (car failure))))
      (displayln "TEST-MODULES-OK modules=" (length files))
      (displayln "OK"))))
