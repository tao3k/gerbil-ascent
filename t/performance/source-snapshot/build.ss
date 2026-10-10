;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
        (only-in :gerbil-ascent/t/native/artifact-admission
                 artifact-sources artifact-matching-sources?))
(export main)
;;; Source closure includes all production owners and qualification imports,
;;; excluding independently edited application and proof modules.
(def (owned-sources)
  (list->hash-table
   (filter (lambda (entry)
             (ormap (lambda (prefix)
                      (string-prefix? prefix (car entry)))
               '("program/" "core/" "table/" "candidate/"
                 "t/qualification/ascent-source-snapshot-test.ss"
                 "t/qualification/ascent-source-log-test.ss"
                 "t/qualification/ascent-withdrawal-session-test.ss"
                 "t/qualification/ascent-timeout-test.ss"
                 "t/qualification/scheme-session-deletion-test.ss"
                 "t/native/artifact-admission.ss" "t/performance/source-snapshot/"
                 "t/performance/source-log/")))
           (hash->list (artifact-sources)))))
(def (main library binary (lane "runner"))
  (unless (member lane '("runner" "qualify")) (error "unknown source snapshot lane" lane))
  (let* ((sources (owned-sources))
         (source (string-append "t/performance/source-snapshot/" lane ".ss")))
    (add-load-path! library)
    (make (append
           '("program/source-snapshot" "program/evaluate" "program/session"
             "t/performance/source-snapshot/reference-evaluate"
             "t/performance/source-snapshot/reference-session"
             "t/performance/source-snapshot/fixture")
           (if (equal? lane "qualify")
             '("t/qualification/ascent-source-snapshot-test"
               "t/qualification/ascent-source-log-test"
               "t/qualification/ascent-withdrawal-session-test"
               "t/qualification/ascent-timeout-test"
               "t/qualification/scheme-session-deletion-test") [])
           (list (path-strip-extension source)))
      srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
      build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (compile-exe source [output-dir: library output-file: binary
                        parallel: #t verbose: #t invoke-gsc: #t static: #t])
    (execute-pending-compile-jobs!)
    (unless (artifact-matching-sources? sources (owned-sources))
      (error "source snapshot sources changed during compilation"))))
