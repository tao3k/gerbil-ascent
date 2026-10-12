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
             (targetRationale . "Admitted dense fresh-axis copy and symmetric closure commit")
             (allocationSampleCount . 5) (baseline . "c3b4da20755141fa2eaff12fe270756cee15b451")
             (allocationTargets chain dense reverse-dense) (targetAllocationRatio . 4/5)
             (scenarios (native-star 11/10 1/50000 0) (native-groups 11/10 1/50000 0) (native-small 11/10 1/50000 0)
                        (dense-cut 11/10 1/50000 0) (reverse-dense 9/10 0 16) (dense 9/10 0 16) (chain 9/10 0 16) (cycle 11/10 1/50000 0) (unique 11/10 1/50000 0) (partitioned 11/10 1/50000 0)
                        (sparse 11/10 1/50000 0) (grouped 11/10 1/50000 0) (retained 11/10 1/50000 0)
                        (capture 11/10 1/50000 0) (cold 11/10 1/50000 0) (small 11/10 1/50000 0)
                        (packed 11/10 1/50000 0) (adjacent 11/10 1/50000 0)
                        (large 11/10 1/50000 0) (eqrel 11/10 1/50000 0))
             (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-UF-DENSE-BULK-EXECUTION 'uf-dense-bulk
                 "Unique-input closure maintenance and complete engine replay"
                 "Initial sparse grouped retained engines and cold small packed EqRel capture controls"
                 "Complete relation sizes and independent closure truth"
                 '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base)))
         (path "t/performance/uf-dense-bulk/benchmark.ss"))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid UF-DENSE-BULK execution fixture"))
    (unless (and (file-exists? path) (equal? contract (call-with-input-file path read)))
      (call-with-output-file [path: path truncate: #t]
        (lambda (out) (write contract out) (newline out))))))
(def (owners)
  (list->hash-table
    (filter (lambda (entry)
              (ormap (lambda (prefix) (string-prefix? prefix (car entry)))
                     '("core/" "program/" "table/" "candidate/"
                       "t/performance/uf-dense-bulk/")))
            (hash->list (artifact-sources)))))
(def (main library)
  (generate-contract!)
  (add-load-path! library)
  (let (sources (owners))
    (make '("table/trrel-uf" "table/storage" "program/initialization" "program/view-replay" "program/view-state" "program/evaluate"
            "t/performance/uf-dense/reference-view-replay"
            "t/performance/uf-dense/reference-view-state"
                        "t/performance/uf-dense/reference-initialization"
            "t/performance/uf-dense/reference-evaluate"
            "t/performance/uf-dense-bulk/reference-trrel-uf"
            "t/performance/uf-dense-bulk/fixture"
            "t/performance/uf-dense-bulk/runner")
      srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
      build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (unless (artifact-matching-sources? sources (owners))
      (error "UF-DENSE-BULK execution owners changed during compilation"))))
