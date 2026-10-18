;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/make :asp-gerbil-scheme/benchmark-api)
(export main)
(def (generate-contract!)
  (let* ((settings
          '((max_total . 999ms) (target_total . 500ms) (regression_budget . 499ms)
            (expected_over_input_budget . 0ms)
            (targetRationale . "Owned weighted export and single-axis bucket visitation")
            (allocationSampleCount . 5) (trajectoriesPerSample . 32) (baseline . "bdae4a23168c5dc0fe96b47fff81d94387849ae8")
            (allocationTargets) (targetAllocationRatio . 4/5)
            (scenarios (heavy 9/10 0 16) (grouped 9/10 0 16)
                       (left-query 9/10 0 16) (right-query 9/10 0 16)
                       (dense 11/10 1/50000 0) (sparse 11/10 1/50000 0) (small 11/10 1/50000 0))
            (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-UF-WEIGHTED-EXECUTION 'uf-weighted
                 "Complete weighted UF view exports and queries"
                 "Thirty-two complete capture+export operations; indexed grouped weighted and sparse/query controls"
                 "Independent Cartesian closure truth and exact ordered rows" '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base)))
         (path "t/performance/uf-weighted/benchmark.ss"))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid UF boundary benchmark contract"))
    (unless (and (file-exists? path) (equal? contract (call-with-input-file path read)))
      (call-with-output-file [path: path truncate: #t] (lambda (out) (write contract out) (newline out))))))
(def (main library)
  (generate-contract!)
  (add-load-path! library)
  (make '("core/relation-view" "table/trrel-uf"
          "t/performance/uf-weighted/reference-relation-view" "t/performance/uf-weighted/reference-trrel-uf"
          "t/performance/uf-weighted/fixture" "t/performance/uf-weighted/runner")
    srcdir: (current-directory) libdir: library parallelize: (##cpu-count)))
