;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
 (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
(def (main library binary (lane "runner"))
 (let* ((sources (artifact-sources)) (source (string-append "t/performance/frozen-routing/" lane ".ss")))
  (unless (member lane '("runner" "qualify")) (error "unknown frozen routing lane" lane))
  (add-load-path! library)
  (make (append (list "core/relation-view" "table/trrel-uf"
                 "t/performance/frozen-routing/reference-view" "t/performance/frozen-routing/reference-uf"
                 (path-strip-extension source))
         (if (equal? lane "qualify")
          '("t/qualification/ascent-relation-view-test" "t/qualification/ascent-provider-views-test"
            "t/qualification/ascent-trrel-uf-test" "t/qualification/ascent-uf-commit-test") []))
    srcdir: (current-directory) libdir: library build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
  (compile-exe source [output-dir: library output-file: binary parallel: #t verbose: #t invoke-gsc: #t static: #t])
  (execute-pending-compile-jobs!)
  (unless (artifact-matching-sources? sources (artifact-sources)) (error "frozen routing sources changed during compilation"))))
