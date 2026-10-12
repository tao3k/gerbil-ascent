;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (prefix-in "build.ss" lookup-) :asp-gerbil-scheme/benchmark-api)
(export main)

;; Run in the isolated study snapshot: the historical lookup contract stays intact.
(def (main library)
  (lookup-main library)
  (let* ((settings
          '((max_total . 999ms) (target_total . 500ms) (regression_budget . 499ms)
            (expected_over_input_budget . 0ms)
            (targetRationale . "Owned selected product collection across left right and grouped queries")
            (allocationSampleCount . 5) (trajectoriesPerSample . 4096)
            (allocationBatchSize . 256)
            (baseline . "268e89b84c487696d5fbf032a10d6dd39479e10a")
            (allocationTargets) (targetAllocationRatio . 4/5)
            (scenarios (complete 9/10 0 16) (union 11/10 1/50000 0)
                       (absent 11/10 1/50000 0) (small 11/10 1/50000 0))
            (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-UF-LOOKUP-EXECUTION 'uf-lookup
                 "Complete selected UF query workflow"
                 "4096 identical left right grouped query workflows and fixed controls"
                 "Independent Cartesian closure truth and exact ordered rows" '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base))))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid selected UF contract"))
    (call-with-output-file [path: "t/performance/uf-lookup/benchmark.ss" truncate: #t]
      (lambda (out) (write contract out) (newline out)))))
