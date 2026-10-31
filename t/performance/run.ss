;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander
        (only-in :gerbil/compiler compile-exe execute-pending-compile-jobs!)
        (only-in :std/make make)
        (only-in :asp-gerbil-scheme/src/build-api/native-spec-support normalize-spec)
        (only-in "../../build-modules.ss" gerbil-ascent-library-spec gerbil-ascent-library-modules gerbil-ascent-compiler-options)
        (only-in :yuanxu/module-system/building/interface call-with-init-build-spec)
        (only-in :std/misc/process run-process)
        (only-in :std/string/uuid random-uuid uuid->string)
        :std/encoding/json
        (only-in :asp-gerbil-scheme/src/build-api/core-capacity
                 initialize-native-build-core-capacity!)
        (only-in :gerbil-ascent/t/harness/artifact-admission
                 artifact-sources artifact-matching-sources? artifact-directory!)
        "studies.ss")
(export main build-study! resolve-study-arguments)

;; BEGIN GENERATED LOOKUP STUDY-PROFILE
(def (study-build-spec module)
  (normalize-spec
    (if (member module (gerbil-ascent-library-modules)) module
      [gxc: module [extra-inputs: [(path-expand "build-modules.ss") (path-expand "t/performance/run.ss")]]])
    gerbil-ascent-compiler-options))

;; END GENERATED LOOKUP STUDY-PROFILE

;; Gerbil owns scheduling, dependencies and object/link completion. A study
;; supplies data, never a second compiler or a benchmark-specific build script.
(def (build-study! study library binary)
  (call-with-init-build-spec gerbil-ascent-library-spec
    (lambda (_native _arguments (prefix #f) (_libdir #f) (_bindir #f))
      (when prefix (error "unexpected foreign performance package" prefix))
      (build-study/native! study library binary))
    '("compile") library))
(def (build-study/native! study library binary)
  (let (sources (artifact-sources))
    (add-load-path! library)
    (initialize-native-build-core-capacity!)
    (make (map study-build-spec (study-modules study))
      srcdir: (current-directory) libdir: library
      build-deps: (path-expand ".cache/ascent/compiled-library/build-deps"))
    (when (study-compiled? study)
      (compile-exe (study-entry study)
        [output-dir: library output-file: binary gsc-options: gerbil-ascent-compiler-options parallel: #t
         verbose: #t invoke-gsc: #t static: #t])
      (execute-pending-compile-jobs!))
    (unless (artifact-matching-sources? sources (artifact-sources))
      (error "performance sources changed during compilation" (study-name study)))))

(def (resolve-study-arguments study scenario library receipt baseline)
  (map (lambda (argument)
    (case argument
      ((scenario) scenario) ((library) library)
      ((receipt) receipt) ((baseline) baseline)
      (else (error "unknown study argument" argument)))) (study-arguments study)))

(def (main name library (baseline "admission") (lane "qualification"))
  (let* ((study (find-study (string->symbol name)))
         (actor? (equal? name "actor-admission"))
         (run-id (uuid->string (random-uuid)))
         (directory (path-expand (string-append ".cache/ascent/" name "/" run-id)))
         (receipts (if actor?
                     (path-expand (string-append ".cache/ascent/actor-" baseline "/" run-id))
                     directory))
         (binary (path-expand "study-entry" directory))
         (sources (artifact-sources))
         (scenarios (if (and actor? (equal? lane "stream")) '("stream")
                      (study-scenarios study))))
    (when actor?
      (unless (and (member baseline '("admission" "coordinator"))
                   (member lane '("qualification" "stream")))
        (error "invalid actor study selection" baseline lane)))
    (artifact-directory! directory)
    (artifact-directory! receipts)
    (displayln "STUDY-RUN " name " receipts=" receipts) (force-output)
    (build-study! study library binary)
    (call-with-output-file (path-expand "sources.json" receipts)
      (lambda (out) (display (json->string sources) out) (newline out)))
    (let (failures [])
      (for-each (lambda (scenario)
        (let* ((receipt (path-expand (string-append scenario (study-receipt-suffix study)) receipts))
               (arguments (resolve-study-arguments study scenario library receipt baseline))
               (command (if (study-compiled? study)
                          (cons binary (cons "-:max-heap=1G,debug=q" arguments))
                          (append ["gxi" "-:max-heap=1G,debug=q"
                            "-e" "(add-load-path! (path-expand \"lib\" (gerbil-path)))"
                            (string-append ":gerbil-ascent/" (path-strip-extension (study-entry study)))]
                            arguments))))
          (with-exception-catcher
            (lambda (failure)
              (if (or (study-keep-going? study) (study-compiled? study))
                (set! failures (cons failure failures))
                (raise failure)))
            (lambda ()
              (run-process (append '("timeout" "90s") command) stdout-redirection: #f))))) scenarios)
      ;; A failed admission gate still needs the same source-identity check.
      ;; Keep the failure and its samples; never skip provenance on rejection.
      (unless (artifact-matching-sources? sources (artifact-sources))
        (error "performance sources changed during measurement" name))
      (unless (null? failures) (raise (car failures))))
    (displayln "STUDY-OK " name " receipts=" receipts)))
