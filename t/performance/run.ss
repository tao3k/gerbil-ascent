;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander
        (only-in :gerbil/compiler compile-exe execute-pending-compile-jobs!)
        (only-in :std/make make)
        (only-in :std/misc/process run-process)
        (only-in :asp-gerbil-scheme/src/build-api/core-capacity
                 initialize-native-build-core-capacity!)
        (only-in :gerbil-ascent/t/native/artifact-admission
                 artifact-sources artifact-matching-sources? artifact-directory!)
        "studies.ss")
(export main build-study! resolve-study-arguments)

;; Gerbil owns scheduling, dependencies and object/link completion. A study
;; supplies data, never a second compiler or a benchmark-specific build script.
(def (build-study! study library binary)
  (let (sources (artifact-sources))
    (add-load-path! library)
    (initialize-native-build-core-capacity!)
    (make (study-modules study)
      srcdir: (current-directory) libdir: library
      build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (when (study-native? study)
      (compile-exe (study-entry study)
        [output-dir: library output-file: binary parallel: #t
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
         (directory (path-expand (string-append ".cache/ascent/" name)))
         (receipts (if actor?
                     (path-expand (string-append ".cache/ascent/actor-" baseline))
                     directory))
         (binary (path-expand "native-entry" directory))
         (scenarios (if (and actor? (equal? lane "stream")) '("stream")
                      (study-scenarios study))))
    (when actor?
      (unless (and (member baseline '("admission" "coordinator"))
                   (member lane '("qualification" "stream")))
        (error "invalid actor study selection" baseline lane)))
    (artifact-directory! directory)
    (artifact-directory! receipts)
    (build-study! study library binary)
    (let (failures [])
      (for-each (lambda (scenario)
        (let* ((receipt (path-expand (string-append scenario (study-receipt-suffix study)) receipts))
               (arguments (resolve-study-arguments study scenario library receipt baseline))
               (command (if (study-native? study)
                          (cons binary (cons "-:max-heap=1G,debug=q" arguments))
                          (append ["gxi" "-:max-heap=1G,debug=q"
                            "-e" "(add-load-path! (path-expand \"lib\" (gerbil-path)))"
                            (string-append ":gerbil-ascent/" (path-strip-extension (study-entry study)))]
                            arguments))))
          (with-exception-catcher
            (lambda (failure)
              (if (study-keep-going? study)
                (set! failures (cons failure failures))
                (raise failure)))
            (lambda ()
              (run-process (append '("timeout" "90s") command) stdout-redirection: #f))))) scenarios)
      (unless (null? failures) (raise (car failures))))))
