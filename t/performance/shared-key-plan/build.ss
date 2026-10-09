;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
 (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
(def (main library binary (lane "runner"))
 (let* ((sources (artifact-sources)) (source (string-append "t/performance/shared-key-plan/" lane ".ss")))
  (unless (member lane '("runner" "qualify")) (error "unknown shared key lane" lane))
  (add-load-path! library)
  (make (append (list "table/index-sharing" "t/performance/shared-key-plan/reference" "t/performance/shared-key-plan/fixture" (path-strip-extension source))
         (if (equal? lane "qualify")
          '("t/qualification/ascent-index-entry-test" "t/qualification/ascent-index-lifecycle-test"
            "t/qualification/ascent-shared-key-plan-test" "t/qualification/ascent-positive-components-test") []))
    srcdir: (current-directory) libdir: library build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
  (compile-exe source [output-dir: library output-file: binary parallel: #t verbose: #t invoke-gsc: #t static: #t])
  (execute-pending-compile-jobs!)
  (unless (artifact-matching-sources? sources (artifact-sources)) (error "shared key sources changed during compilation"))))
