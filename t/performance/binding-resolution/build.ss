;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
 (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
(def (main library binary (lane "runner"))
 (let* ((sources (artifact-sources)) (source (string-append "t/performance/binding-resolution/" lane ".ss")))
  (unless (member lane '("runner" "qualify")) (error "unknown Binding resolution lane" lane))
  (add-load-path! library)
  (make (append (list "program/operator-analysis" "program/operator-lowering" "program/operator"
    "t/performance/binding-resolution/reference" "t/performance/binding-resolution/fixture" "t/performance/lexical-dependencies/fixture"
    (path-strip-extension source))
    (if (equal? lane "qualify")
      (quote ("t/qualification/scheme-operator-test" "t/qualification/scheme-operator-retained-test"
       "t/qualification/scheme-higher-order-test" "t/qualification/ascent-binding-resolution-test")) []))
    srcdir: (current-directory) libdir: library build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
  (compile-exe source [output-dir: library output-file: binary parallel: #t verbose: #t invoke-gsc: #t static: #t])
  (execute-pending-compile-jobs!)
  (unless (artifact-matching-sources? sources (artifact-sources)) (error "Binding resolution sources changed during compilation"))))
