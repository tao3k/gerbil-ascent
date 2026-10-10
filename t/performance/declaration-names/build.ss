;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
        (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
;;; Bind the actual production and native fixture owners. Concurrent application
;;; changes are outside this dependency closure and do not alter these consumers.
(def (owned-sources)
  (list->hash-table
   (filter (lambda (entry)
             (ormap (lambda (prefix) (string-prefix? prefix (car entry)))
               '("program/" "core/" "table/" "candidate/"
                 "t/performance/declaration-names/" "t/performance/candidate-flow/"
                 "t/qualification/ascent-declaration-names-test.ss"
                 "t/qualification/ascent-poo-primitives-test.ss"
                 "t/qualification/ascent-candidate-flow-test.ss"
                 "t/native/artifact-admission.ss")))
           (hash->list (artifact-sources)))))
(def (main library binary (lane "runner"))
  (unless (member lane '("runner" "qualify")) (error "unknown declaration names lane" lane))
  (let ((sources (owned-sources))
        (source (string-append "t/performance/declaration-names/" lane ".ss")))
    (add-load-path! library)
    (make (append '("program/objects" "t/performance/declaration-names/reference"
                   "t/performance/declaration-names/fixture")
                  (if (equal? lane "qualify")
                    '("t/qualification/ascent-declaration-names-test"
                      "t/qualification/ascent-poo-primitives-test"
                      "t/qualification/ascent-candidate-flow-test") [])
                  (list (path-strip-extension source)))
      srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
      build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (compile-exe source [output-dir: library output-file: binary parallel: #t
                        verbose: #t invoke-gsc: #t static: #t])
    (execute-pending-compile-jobs!)
    (unless (artifact-matching-sources? sources (owned-sources))
      (error "declaration names sources changed during compilation"))))
