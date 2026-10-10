;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
        (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
(def (main library binary (lane "runner"))
  (unless (member lane '("runner" "qualify")) (error "unknown typed admission lane" lane))
  (let ((sources (artifact-sources))
        (source (string-append "t/performance/typed-admission/" lane ".ss")))
    (add-load-path! library)
    (make (append '("program/higher-order" "t/performance/typed-admission/reference"
                   "t/performance/typed-admission/fixture")
                  (if (equal? lane "qualify")
                    '("t/qualification/scheme-higher-order-test"
                      "t/qualification/ascent-typed-domain-test") [])
                  (list (path-strip-extension source)))
      srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
      build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (compile-exe source [output-dir: library output-file: binary parallel: #t
                        verbose: #t invoke-gsc: #t static: #t])
    (execute-pending-compile-jobs!)
    (unless (artifact-matching-sources? sources (artifact-sources))
      (error "typed admission sources changed during compilation"))))
