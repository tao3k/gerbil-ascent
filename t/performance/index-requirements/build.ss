;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
 (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
(def (main library binary (lane "runner"))
 (let* ((sources (artifact-sources)) (source (string-append "t/performance/index-requirements/" lane ".ss")))
  (unless (member lane '("runner" "qualify")) (error "unknown index requirement lane" lane))
  (add-load-path! library)
  (make (append (list "program/index" "program/component-worker" "t/performance/index-requirements/reference" "t/performance/index-requirements/fixture" (path-strip-extension source))
         (if (equal? lane "qualify")
          '("t/qualification/ascent-index-entry-test" "t/qualification/ascent-index-lifecycle-test"
            "t/qualification/ascent-index-requirements-test" "t/qualification/ascent-positive-components-test") []))
    srcdir: (current-directory) libdir: library build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
  (compile-exe source [output-dir: library output-file: binary parallel: #t verbose: #t invoke-gsc: #t static: #t])
  (execute-pending-compile-jobs!)
  (unless (artifact-matching-sources? sources (artifact-sources)) (error "index requirement sources changed during compilation"))))
