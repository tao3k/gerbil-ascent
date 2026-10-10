;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/make :gerbil/compiler
        (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
(def (main library binary)
  (def sources (artifact-sources))
  (add-load-path! library)
  (make '("candidate/withdrawal-session" "t/performance/withdrawal-support/replay-reference"
          "t/performance/withdrawal-support/runner")
    srcdir: (current-directory) libdir: library
    build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
  (compile-exe "t/performance/withdrawal-support/runner.ss"
    [output-dir: library output-file: binary parallel: #t verbose: #t invoke-gsc: #t static: #t])
  (execute-pending-compile-jobs!)
  (unless (artifact-matching-sources? sources (artifact-sources))
    (error "support performance sources changed during compilation")))
