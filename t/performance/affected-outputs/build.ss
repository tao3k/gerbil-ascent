;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
 (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
(def (main library binary (lane "runner"))
 (let* ((sources (artifact-sources)) (source (string-append "t/performance/affected-outputs/" lane ".ss")))
  (unless (member lane '("runner" "qualify")) (error "unknown Affected outputs lane" lane))
  (add-load-path! library)
  (make (append '("core/ordered-call" "core/expression-plan" "core/rule-bindings" "core/positive-plan" "program/update-selection"
   "t/performance/affected-outputs/reference"
   "t/performance/affected-outputs/fixture") (list (path-strip-extension source))
   (if (equal? lane "qualify")
    '("t/qualification/ascent-selected-activation-test" "t/qualification/ascent-positive-components-test"
      "t/qualification/ascent-affected-outputs-test") []))
   srcdir: (current-directory) libdir: library build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
  (compile-exe source [output-dir: library output-file: binary parallel: #t verbose: #t invoke-gsc: #t static: #t])
  (execute-pending-compile-jobs!)
  (unless (artifact-matching-sources? sources (artifact-sources)) (error "Affected outputs sources changed during compilation"))))
