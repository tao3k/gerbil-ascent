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
             (targetRationale . "Sparse UF publication/export and immutable cut capture")
             (allocationSampleCount . 5) (baseline . "3d74647dcc4a23c74cbd56e93b6d9cba91a582a5")
             (scenarios (sparse 9/10 0 16) (grouped 9/10 0 16) (retained 9/10 0 16) (capture 9/10 0 16)
                        (cold 11/10 1/50000 0) (small 11/10 1/50000 0)
                        (packed 11/10 1/50000 0) (eqrel 11/10 1/50000 0))
             (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-UF-EXPORT-EXECUTION 'uf-export
                 "Sparse UF engine publication and frozen cut capture"
                 "Sparse grouped retained engines, cut capture and cold small packed EqRel controls"
                 "Complete relation sizes and independent closure truth"
                 '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base)))
         (path "t/performance/uf-export/benchmark.ss"))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid UF-EXPORT execution fixture"))
    (unless (and (file-exists? path) (equal? contract (call-with-input-file path read)))
      (call-with-output-file [path: path truncate: #t]
        (lambda (out) (write contract out) (newline out))))))
(def (owners)
  (list->hash-table
    (filter (lambda (entry)
              (ormap (lambda (prefix) (string-prefix? prefix (car entry)))
                     '("core/" "program/" "table/" "candidate/"
                       "t/performance/uf-export/")))
            (hash->list (artifact-sources)))))
(def (main library)
  (generate-contract!)
  (add-load-path! library)
  (let (sources (owners))
    (make '("core/relation-view" "table/trrel-uf" "program/view-state" "program/evaluate"
            "t/performance/uf-export/reference-trrel-uf"
            "t/performance/uf-export/reference-view-state"
            "t/performance/uf-export/reference-evaluate"
            "t/performance/uf-export/fixture"
            "t/performance/uf-export/runner")
      srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
      build-deps: (path-expand ".cache/ascent/compiled-library/build-deps"))
    (unless (artifact-matching-sources? sources (owners))
      (error "UF-EXPORT execution owners changed during compilation"))))
