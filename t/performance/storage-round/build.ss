;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :std/make
        (only-in :asp-gerbil-scheme/benchmark-api make-benchmark-fixture benchmark-fixture-contract-pass?)
        (only-in :gerbil-ascent/t/harness/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
;;; Generate the checked benchmark datum through ASP's native fixture API.
;;; These explicit settings preserve the gates fixed before the first sample.
(def (generate-contract!)
  (let* ((settings
           '((max_total . 999ms) (target_total . 500ms) (regression_budget . 499ms)
             (expected_over_input_budget . 0ms)
             (targetRationale . "Custom storage workspace, readiness and complete publication")
             (allocationSampleCount . 5) (baseline . "252706d119b798072f521a9321e42111804a9f9f")
             (scenarios (wide 9/10 0 16) (retained 9/10 0 16) (mixed 9/10 0 16)
                        (cold 11/10 1/50000 0) (small 11/10 1/50000 0)
                        (dense 11/10 1/50000 0) (index 11/10 1/50000 0) (native 11/10 1/50000 0))
             (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-STORAGE-ROUND-EXECUTION 'storage-round
                 "Complete custom storage engine publication"
                 "Custom recursion, retained updates and mixed storage with complete controls"
                 "Complete relation sizes and independent closure truth"
                 '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base)))
         (path "t/performance/storage-round/benchmark.ss"))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid STORAGE-ROUND execution fixture"))
    (unless (and (file-exists? path) (equal? contract (call-with-input-file path read)))
      (call-with-output-file [path: path truncate: #t]
        (lambda (out) (write contract out) (newline out))))))
(def (owners)
  (list->hash-table
    (filter (lambda (entry)
              (ormap (lambda (prefix) (string-prefix? prefix (car entry)))
                     '("core/" "program/" "table/" "candidate/"
                       "t/performance/storage-round/")))
            (hash->list (artifact-sources)))))
(def (main library)
  (generate-contract!)
  (add-load-path! library)
  (let (sources (owners))
    (make '("table/storage" "program/initialization" "program/round-workspace" "program/evaluate"
            "t/performance/storage-round/reference-round-workspace"
            "t/performance/storage-round/reference-evaluate"
            "t/performance/storage-round/fixture"
            "t/performance/storage-round/runner")
      srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
      build-deps: (path-expand ".cache/ascent/compiled-library/build-deps"))
    (unless (artifact-matching-sources? sources (owners))
      (error "STORAGE-ROUND execution owners changed during compilation"))))
