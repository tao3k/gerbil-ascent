;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/make :asp-gerbil-scheme/benchmark-api)
(export main)
(def (generate-contract!)
  (let* ((settings
          '((max_total . 999ms) (target_total . 500ms) (regression_budget . 499ms)
            (expected_over_input_budget . 0ms)
            (targetRationale . "Frozen UF full-row materialization and grouped ordered replay")
            (allocationSampleCount . 5) (trajectoriesPerSample . 32) (baseline . "81d7f83225de35821d262de1d43cc912dd96f03a")
            (allocationTargets dense grouped) (targetAllocationRatio . 4/5)
            (scenarios (dense 9/10 0 16) (grouped 9/10 0 16) (replay 11/10 1/50000 0)
                       (sparse 11/10 1/50000 0) (small 11/10 1/50000 0) (delta 11/10 1/50000 0)
                       (select 11/10 1/50000 0))
            (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-UF-MATERIALIZATION-EXECUTION 'uf-materialization
                 "Complete immutable UF view exports"
                 "Thirty-two complete exports per sample; dense grouped replay and sparse small selective controls"
                 "Independent Cartesian closure truth and exact ordered rows" '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base)))
         (path "t/performance/uf-materialization/benchmark.ss"))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid UF boundary benchmark contract"))
    (unless (and (file-exists? path) (equal? contract (call-with-input-file path read)))
      (call-with-output-file [path: path truncate: #t] (lambda (out) (write contract out) (newline out))))))
(def (main library)
  (generate-contract!)
  (add-load-path! library)
  (make '("core/relation-view" "program/view-replay" "program/view-state"
          "t/performance/uf-materialization/reference-relation-view"
          "t/performance/uf-dense/reference-view-replay"
          "t/performance/uf-materialization/reference-view-state"
          "t/performance/uf-materialization/fixture" "t/performance/uf-materialization/runner")
    srcdir: (current-directory) libdir: library parallelize: (##cpu-count)))
