;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
        (only-in :gerbil-ascent/t/runner/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
;; Compilation belongs to the test lane; the production build remains declarative.
(def (main library binary)
  (let (sources (artifact-sources))
    (add-load-path! library)
    (make ["program/actor-round" "t/performance/actor-admission/reference"
           "t/performance/actor-coordinator/reference" "t/performance/actor-admission-benchmark"]
          srcdir: (current-directory) libdir: library
          build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (let ((source "t/performance/actor-admission-native.ss")
          (options [output-dir: library output-file: binary
                    parallel: #t verbose: #t invoke-gsc: #t static: #t]))
      (compile-module source [invoke-gsc: #f options ...])
      (compile-exe source options)
      (execute-pending-compile-jobs!))
    (unless (artifact-matching-sources? sources (artifact-sources))
      (error "actor benchmark sources changed during native compilation"))))
