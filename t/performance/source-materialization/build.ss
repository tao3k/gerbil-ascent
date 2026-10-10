;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/make
        (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
;;; Bind production and the actual native fixture closure. Independent
;;; application/proof edits do not change these source consumers.
(def (owned-sources)
  (list->hash-table
   (filter (lambda (entry)
             (ormap (lambda (prefix) (string-prefix? prefix (car entry)))
               '("program/" "core/" "table/" "candidate/"
                 "t/performance/source-materialization/" "t/performance/source-snapshot/"
                 "t/performance/source-log/" "t/performance/storage-batch/"
                 "t/qualification/ascent-source-" "t/qualification/ascent-timeout-test.ss"
                 "t/qualification/ascent-storage-batch-test.ss"
                 "t/qualification/ascent-initial-admission-test.ss"
                 "t/qualification/ascent-withdrawal-session-test.ss"
                 "t/native/artifact-admission.ss")))
           (hash->list (artifact-sources)))))
(def (main library)
  (let (sources (owned-sources))
    (make '("program/initialization" "program/source-snapshot" "program/update-selection" "program/result" "program/reuse"
            "program/evaluate" "program/session"
          "t/performance/source-materialization/reference-initialization"
          "t/performance/source-materialization/reference-snapshot"
          "t/performance/source-materialization/reference-result"
          "t/performance/source-materialization/reference-selection"
          "t/performance/source-materialization/reference-reuse"
          "t/performance/source-materialization/reference-evaluate"
          "t/performance/source-materialization/reference-session"
          "t/performance/source-materialization/fixture")
    srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
      build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (unless (artifact-matching-sources? sources (owned-sources))
      (error "source materialization owners changed during compilation"))))
