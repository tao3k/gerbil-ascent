;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/make make)
        (only-in :std/misc/process run-process)
        (only-in :std/string/misc string-contains)
        :std/encoding/json
        (only-in :asp-gerbil-scheme/src/build-api/core-capacity
                 initialize-native-build-core-capacity!)
        (only-in :gerbil-ascent/t/native/artifact-admission
                 artifact-sources artifact-matching-sources? artifact-directory!)
        "reference-studies.ss")
(export main)

(def (build-reference! study library)
  (let (sources (artifact-sources))
    (add-load-path! library)
    (initialize-native-build-core-capacity!)
    (make (reference-study-modules study)
      srcdir: (current-directory) libdir: library
      build-deps: (path-expand "build-deps" (path-directory library)))
    (unless (artifact-matching-sources? sources (artifact-sources))
      (error "reference sources changed during compilation" (reference-study-name study)))))

(def (run-reference! study library receipt)
  (let ((results 0) (complete? #f) (error? #f))
    (run-process
      ["timeout" (string-append (number->string (reference-study-run-seconds study)) "s")
       "gxi" "-:max-heap=1G,debug=q" (reference-study-entry study) receipt]
      stdout-redirection: #t stderr-redirection: #t
      coprocess: (lambda (input)
        (let loop ()
          (let (line (read-line input))
            (unless (eof-object? line)
              (displayln line) (force-output)
              (when (string-prefix? "RESULT " line) (set! results (+ results 1)))
              (when (string=? "OK" line) (set! complete? #t))
              (when (or (string-contains line "ERROR")
                        (string-contains line "Heap overflow")
                        (string-contains line "Stack overflow")) (set! error? #t))
              (loop))))))
    (unless (and (not error?) complete? (= results (reference-study-results study)))
      (error "reference benchmark did not complete its Cases" (reference-study-name study) results))))

(def (main name dependencies (mode "run"))
  (let* ((study (find-reference-study (string->symbol name)))
         (directory (path-expand (string-append ".cache/ascent/reference/" name)))
         (library (path-expand "lib" directory))
         (receipt (path-expand "receipt.sexp" directory)))
    (unless (member mode '("build" "run")) (error "invalid reference mode" mode))
    (artifact-directory! library)
    (setenv "GERBIL_LOADPATH"
      (string-append library ":" dependencies ":" (getenv "GERBIL_LOADPATH" "")))
    (if (string=? mode "build")
      (build-reference! study library)
      (let (sources (artifact-sources))
        (run-process
          ["timeout" (string-append (number->string (reference-study-build-seconds study)) "s")
           "gxi" "-:max-heap=1G,debug=q" "t/performance/reference-run.ss" name dependencies "build"]
          stdout-redirection: #f)
        (call-with-output-file [path: (string-append receipt ".sources") truncate: #t]
          (lambda (out) (display (json->string sources) out) (newline out)))
        (run-reference! study library receipt)
        (unless (artifact-matching-sources? sources (artifact-sources))
          (error "reference sources changed during measurement" name))))))
