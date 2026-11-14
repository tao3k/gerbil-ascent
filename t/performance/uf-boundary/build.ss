;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/make :asp-gerbil-scheme/benchmark-api)
(export main)
(def (generate-contract!)
  (let* ((settings
          '((max_total . 999ms) (target_total . 500ms) (regression_budget . 499ms)
            (expected_over_input_budget . 0ms)
            (targetRationale . "Existing-endpoint bitmap differences and SCC boundary retirement")
            (allocationSampleCount . 5) (baseline . "0ec0f436951ee7f84bb1d535733145c255ece05b")
            (allocationTargets) (targetAllocationRatio . 4/5)
            (scenarios (bridge 9/10 0 16) (partial 9/10 0 16) (complete 9/10 0 16)
                       (overlap 11/10 1/50000 0) (weighted 11/10 1/50000 0)
                       (sparse 11/10 1/50000 0) (small 11/10 1/50000 0) (chain 11/10 1/50000 0))
            (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-UF-BOUNDARY-EXECUTION 'uf-boundary
                 "Complete UF closure input trajectories"
                 "Existing-endpoint bridge and partial/complete SCC; sparse small chain controls"
                 "Independent closure mass and component/arc counts" '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base)))
         (path "t/performance/uf-boundary/benchmark.ss"))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid UF boundary benchmark contract"))
    (unless (and (file-exists? path) (equal? contract (call-with-input-file path read)))
      (call-with-output-file [path: path truncate: #t] (lambda (out) (write contract out) (newline out))))))
(def (main library)
  (generate-contract!)
  (add-load-path! library)
  (make '("table/trrel-uf" "t/performance/uf-boundary/reference-trrel-uf"
          "t/performance/uf-boundary/fixture" "t/performance/uf-boundary/runner")
    srcdir: (current-directory) libdir: library parallelize: (##cpu-count)))
