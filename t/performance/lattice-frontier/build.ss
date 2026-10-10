;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/make
        (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
;;; Bind the actual production and native fixture owners. Concurrent application
;;; changes are outside this dependency closure and do not alter these consumers.
(def (owned-sources)
  (list->hash-table
   (filter (lambda (entry)
             (ormap (lambda (prefix) (string-prefix? prefix (car entry)))
               '("program/" "core/" "table/" "candidate/"
                 "t/performance/lattice-frontier/" "t/performance/storage-batch/"
                 "t/qualification/ascent-lattice-"
                 "t/qualification/ascent-storage-batch-test.ss"
                 "t/native/artifact-admission.ss")))
           (hash->list (artifact-sources)))))
(def (main library)
  (let (sources (owned-sources))
    (make '("program/lattice-frontier" "program/initialization" "program/evaluate"
            "t/performance/lattice-frontier/reference-initialization"
            "t/performance/lattice-frontier/reference"
            "t/performance/lattice-frontier/fixture")
      srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
      build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (unless (artifact-matching-sources? sources (owned-sources))
      (error "lattice frontier sources changed during compilation"))))
