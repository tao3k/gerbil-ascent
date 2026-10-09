;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
 (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
(def (main library binary (lane "runner"))
 (let* ((sources (artifact-sources)) (source (string-append "t/performance/provider-packet/" lane ".ss")))
  (unless (member lane '("runner" "qualify")) (error "unknown Provider packet lane" lane))
  (add-load-path! library)
  (make (append '("table/funs" "program/index"
   "t/performance/provider-packet/reference"
   "t/performance/provider-packet/fixture") (list (path-strip-extension source))
   (if (equal? lane "qualify")
    '("t/qualification/ascent-byods-index-test"
      "t/qualification/ascent-provider-packet-test"
      "t/qualification/ascent-index-lifecycle-test") []))
   srcdir: (current-directory) libdir: library build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
  (compile-exe source [output-dir: library output-file: binary parallel: #t verbose: #t invoke-gsc: #t static: #t])
  (execute-pending-compile-jobs!)
  (unless (artifact-matching-sources? sources (artifact-sources)) (error "Provider packet sources changed during compilation"))))
