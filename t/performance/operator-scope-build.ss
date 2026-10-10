;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
        (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
(def (main library binary)
  (let (sources (artifact-sources))
    (add-load-path! library)
    (make ["program/operator-descriptor" "program/operator-analysis" "program/operator-measurement" "program/operator-reference" "program/operator" "t/performance/operator-scope/reference" "t/performance/operator-scope-benchmark"]
          srcdir: (current-directory) libdir: library build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (let ((source "t/performance/operator-scope-benchmark.ss")
          (options [output-dir: library output-file: binary parallel: #t verbose: #t invoke-gsc: #t static: #t]))
      ;; make already compiled this module; link its admitted objects directly.
      (compile-exe source options) (execute-pending-compile-jobs!))
    (unless (artifact-matching-sources? sources (artifact-sources)) (error "operator scope benchmark sources changed during compilation"))))
