;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/make :asp-gerbil-scheme/benchmark-api)
(export main)
(def (generate-contract!)
  (let* ((settings
          '((max_total . 999ms) (target_total . 500ms) (regression_budget . 499ms)
            (expected_over_input_budget . 0ms)
            (targetRationale . "Owned complete query materialization without stream or reverse copy")
            (allocationSampleCount . 5) (trajectoriesPerSample . 2048) (baseline . "a9d624a7c21526b0b6fe8ca19fd6dba40942c310")
            (allocationTargets left right grouped) (targetAllocationRatio . 4/5)
            (scenarios (left 9/10 0 16) (right 9/10 0 16)
                       (grouped 9/10 0 16) (union 11/10 1/50000 0)
                       (absent 11/10 1/50000 0) (small 11/10 1/50000 0))
            (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-UF-LOOKUP-EXECUTION 'uf-lookup
                 "Complete weighted UF view exports and queries"
                 "2048 complete native lookup or frozen union exports; grouped absent and small controls"
                 "Independent Cartesian closure truth and exact ordered rows" '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base)))
         (path "t/performance/uf-lookup/benchmark.ss"))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid UF boundary benchmark contract"))
    (unless (and (file-exists? path) (equal? contract (call-with-input-file path read)))
      (call-with-output-file [path: path truncate: #t] (lambda (out) (write contract out) (newline out))))))
(def (main library)
  (generate-contract!)
  (add-load-path! library)
  (make '("core/relation-view" "table/trrel-uf"
          "t/performance/uf-lookup/reference-relation-view" "t/performance/uf-lookup/reference-trrel-uf"
          "t/performance/uf-lookup/fixture" "t/performance/uf-lookup/runner")
    srcdir: (current-directory) libdir: library parallelize: (##cpu-count)))
