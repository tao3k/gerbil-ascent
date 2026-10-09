;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
 (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
(def (main library binary (lane "runner"))
 (let* ((sources (artifact-sources)) (source (string-append "t/performance/ordered-call/" lane ".ss")))
  (unless (member lane '("runner" "qualify")) (error "unknown Ordered call lane" lane))
  (add-load-path! library)
  (make (append '("core/ordered-call" "core/expression-plan" "core/rule-bindings"
   "t/performance/ordered-call/bindings-reference" "t/performance/ordered-call/frame-reference"
   "t/performance/ordered-call/fixture") (list (path-strip-extension source))
   (if (equal? lane "qualify")
    '("t/qualification/ascent-callback-plan-test" "t/qualification/ascent-expression-plan-test"
      "t/qualification/ascent-rule-bindings-test" "t/qualification/ascent-ordered-call-test") []))
   srcdir: (current-directory) libdir: library build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
  (compile-exe source [output-dir: library output-file: binary parallel: #t verbose: #t invoke-gsc: #t static: #t])
  (execute-pending-compile-jobs!)
  (unless (artifact-matching-sources? sources (artifact-sources)) (error "Ordered call sources changed during compilation"))))
