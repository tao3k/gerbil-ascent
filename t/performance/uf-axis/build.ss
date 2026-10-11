;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :std/make
        (only-in :asp-gerbil-scheme/benchmark-api make-benchmark-fixture benchmark-fixture-contract-pass?)
        (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
;;; Generate the checked benchmark datum through ASP's native fixture API.
;;; These explicit settings preserve the gates fixed before the first sample.
(def (generate-contract!)
  (let* ((settings
           '((max_total . 999ms) (target_total . 500ms) (regression_budget . 499ms)
             (expected_over_input_budget . 0ms)
             (targetRationale . "Fresh UF products and monotone replay axis witnesses")
             (allocationSampleCount . 5) (baseline . "e17bd86eca696dc2aa7220c22ad1424f9b49cb9e")
             (scenarios (chain 9/10 0 16) (cycle 9/10 0 16) (unique 9/10 0 16) (partitioned 9/10 0 16)
                        (sparse 11/10 1/50000 0) (grouped 11/10 1/50000 0) (retained 11/10 1/50000 0)
                        (capture 11/10 1/50000 0) (cold 11/10 1/50000 0) (small 11/10 1/50000 0)
                        (packed 11/10 1/50000 0) (adjacent 11/10 1/50000 0)
                        (large 11/10 1/50000 0) (eqrel 11/10 1/50000 0))
             (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-UF-AXIS-EXECUTION 'uf-axis
                 "Unique-input closure maintenance and complete engine replay"
                 "Initial sparse grouped retained engines and cold small packed EqRel capture controls"
                 "Complete relation sizes and independent closure truth"
                 '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base)))
         (path "t/performance/uf-axis/benchmark.ss"))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid UF-AXIS execution fixture"))
    (unless (and (file-exists? path) (equal? contract (call-with-input-file path read)))
      (call-with-output-file [path: path truncate: #t]
        (lambda (out) (write contract out) (newline out))))))
(def (owners)
  (list->hash-table
    (filter (lambda (entry)
              (ormap (lambda (prefix) (string-prefix? prefix (car entry)))
                     '("core/" "program/" "table/" "candidate/"
                       "t/performance/uf-axis/")))
            (hash->list (artifact-sources)))))
(def (main library)
  (generate-contract!)
  (add-load-path! library)
  (let (sources (owners))
    (make '("table/trrel-uf" "table/storage" "program/initialization" "program/view-replay" "program/view-state" "program/evaluate"
            "t/performance/uf-axis/reference-view-replay"
            "t/performance/uf-axis/reference-view-state"
                        "t/performance/uf-axis/reference-initialization"
            "t/performance/uf-axis/reference-evaluate"
            "t/performance/uf-axis/reference-trrel-uf"
            "t/performance/uf-axis/fixture"
            "t/performance/uf-axis/runner")
      srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
      build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (unless (artifact-matching-sources? sources (owners))
      (error "UF-AXIS execution owners changed during compilation"))))
