;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/make :asp-gerbil-scheme/benchmark-api)
(export main)
(def (generate-contract!)
  (let* ((settings
          '((max_total . 999ms) (target_total . 500ms) (regression_budget . 499ms)
            (expected_over_input_budget . 0ms)
            (targetRationale . "Ordered singleton-source capture and query-local member routing")
            (allocationSampleCount . 5) (trajectoriesPerSample . 8) (baseline . "b77fdf19049326890aafbe1a207fce231cfae8a4")
            (allocationTargets dense grouped indexed) (targetAllocationRatio . 4/5)
            (scenarios (dense 9/10 0 16) (grouped 9/10 0 16) (indexed 9/10 0 16)
                       (weighted 11/10 1/50000 0) (query 11/10 1/50000 0)
                       (sparse 11/10 1/50000 0) (small 11/10 1/50000 0))
            (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-UF-CAPTURE-EXECUTION 'uf-capture
                 "Complete immutable UF view exports"
                 "Eight complete capture+export operations; indexed grouped weighted and sparse/query controls"
                 "Independent Cartesian closure truth and exact ordered rows" '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base)))
         (path "t/performance/uf-capture/benchmark.ss"))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid UF boundary benchmark contract"))
    (unless (and (file-exists? path) (equal? contract (call-with-input-file path read)))
      (call-with-output-file [path: path truncate: #t] (lambda (out) (write contract out) (newline out))))))
(def (main library)
  (generate-contract!)
  (add-load-path! library)
  (make '("core/relation-view" "table/trrel-uf"
          "t/performance/uf-capture/reference-relation-view" "t/performance/uf-capture/reference-trrel-uf"
          "t/performance/uf-capture/fixture" "t/performance/uf-capture/runner")
    srcdir: (current-directory) libdir: library parallelize: (##cpu-count)))
