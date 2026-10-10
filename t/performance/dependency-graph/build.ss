;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
 (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
(def (main library binary (lane "runner"))
 (let* ((sources (artifact-sources))
        (source (string-append "t/performance/dependency-graph/" lane ".ss")))
  (unless (member lane '("runner" "qualify")) (error "unknown graph lane" lane))
  (add-load-path! library)
  (make (list "core/dependency-graph" "t/performance/dependency-graph/reference" (path-strip-extension source))
   srcdir: (current-directory) libdir: library
   build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
  (compile-exe source [output-dir: library output-file: binary parallel: #t verbose: #t invoke-gsc: #t static: #t])
  (execute-pending-compile-jobs!)
  (unless (artifact-matching-sources? sources (artifact-sources)) (error "graph sources changed during compilation"))))
