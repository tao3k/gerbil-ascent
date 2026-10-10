;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/make :gerbil/compiler
        (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
(def (main library binary)
  (def sources (artifact-sources))
  (add-load-path! library)
  (make '("program/operator-analysis" "program/operator-change"
          "t/performance/mapping-lookup/reference" "t/performance/mapping-lookup/fixture"
          "t/performance/change-plan-runner")
    srcdir: (current-directory) libdir: library
    build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
  (compile-exe "t/performance/change-plan-runner.ss"
    [output-dir: library output-file: binary parallel: #t verbose: #t invoke-gsc: #t static: #t])
  (execute-pending-compile-jobs!)
  (unless (artifact-matching-sources? sources (artifact-sources))
    (error "change plan sources changed during compilation")))
