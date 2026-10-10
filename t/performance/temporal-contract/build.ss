;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
 (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
(def (main library binary (lane "runner"))
 (let* ((sources (artifact-sources)) (source (string-append "t/performance/temporal-contract/" lane ".ss")))
  (unless (member lane '("runner" "qualify")) (error "unknown Temporal contract lane" lane))
  (add-load-path! library)
  (make (append '("temporal/value" "temporal/projection" "temporal/lens"
   "t/performance/temporal-contract/reference"
   "t/performance/temporal-contract/fixture") (list (path-strip-extension source))
   (if (equal? lane "qualify")
    '("t/qualification/ascent-temporal-lens-test"
      "t/qualification/ascent-temporal-contract-test"
      "t/qualification/ascent-temporal-projection-test") []))
   srcdir: (current-directory) libdir: library build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
  (compile-exe source [output-dir: library output-file: binary parallel: #t verbose: #t invoke-gsc: #t static: #t])
  (execute-pending-compile-jobs!)
  (unless (artifact-matching-sources? sources (artifact-sources)) (error "Temporal contract sources changed during compilation"))))
