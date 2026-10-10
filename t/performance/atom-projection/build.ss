;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
        (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
(def (main library binary (lane "benchmark"))
  (let (sources (artifact-sources))
    (add-load-path! library)
    (def source
      (case lane
        (("benchmark") "t/performance/atom-projection/runner.ss")
        (("qualification") "t/performance/atom-projection/qualify.ss")
        (else (error "unknown atom projection build lane" lane))))
    (make (append '("core/relation-view" "core/rule-bindings" "core/expression-plan" "core/positive-plan" "t/performance/atom-projection/reference" "t/performance/atom-projection/runner") (list (path-strip-extension source))
      (if (equal? lane "qualification")
        '("t/performance/component-scope/reference" "t/performance/component-scope/fixture") []))
      srcdir: (current-directory) libdir: library
      build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (compile-exe source
      [output-dir: library output-file: binary parallel: #t verbose: #t invoke-gsc: #t static: #t])
    (execute-pending-compile-jobs!)
    (unless (artifact-matching-sources? sources (artifact-sources))
      (error "atom projection sources changed during compilation"))))
