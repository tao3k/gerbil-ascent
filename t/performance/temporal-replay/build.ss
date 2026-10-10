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
                     '("temporal/" "candidate/" "core/" "program/" "table/"
                       "t/performance/temporal-replay/")))
            (hash->list (artifact-sources)))))
(def (main library)
  (let (sources (owners))
    (make '("temporal/lens" "t/performance/temporal-replay/reference"
            "t/performance/temporal-replay/fixture")
      srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
      build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (unless (artifact-matching-sources? sources (owners))
      (error "temporal replay owners changed during compilation"))))
