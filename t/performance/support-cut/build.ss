;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/make
        (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
(def (owners)
  (list->hash-table
   (filter (lambda (entry)
             (ormap (lambda (prefix) (string-prefix? prefix (car entry)))
                    '("candidate/" "program/" "core/" "table/" "t/performance/support-cut/"
                      "t/qualification/ascent-support-cut-test.ss")))
           (hash->list (artifact-sources)))))
(def (main library)
  (let (sources (owners))
  (make '("candidate/support-dependencies" "candidate/support-cut" "candidate/support-height" "candidate/provenance-maintenance" "candidate/provenance-graph"
          "candidate/withdrawal-session" "t/performance/support-cut/reference"
          "t/performance/support-cut/fixture")
    srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
    build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (unless (artifact-matching-sources? sources (owners))
      (error "support height owners changed during compilation"))))
