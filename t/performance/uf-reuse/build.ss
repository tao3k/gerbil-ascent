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
             (targetRationale . "Interleaved UF admission and bounded vertex replay planning")
             (allocationSampleCount . 5) (baseline . "86f6f9e3928971420389c3d214865fd70b3128b6")
             (scenarios (initial 9/10 0 16) (sparse 9/10 0 16) (grouped 9/10 0 16) (retained 9/10 0 16) (capture 11/10 1/50000 0)
                        (cold 11/10 1/50000 0) (small 11/10 1/50000 0)
                        (packed 11/10 1/50000 0) (adjacent 11/10 1/50000 0)
                        (large 11/10 1/50000 0) (eqrel 11/10 1/50000 0))
             (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-UF-REUSE-EXECUTION 'uf-reuse
                 "Complete interleaved UF publication and replay"
                 "Initial sparse grouped retained engines and cold small packed EqRel capture controls"
                 "Complete relation sizes and independent closure truth"
                 '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base)))
         (path "t/performance/uf-reuse/benchmark.ss"))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid UF-REUSE execution fixture"))
    (unless (and (file-exists? path) (equal? contract (call-with-input-file path read)))
      (call-with-output-file [path: path truncate: #t]
        (lambda (out) (write contract out) (newline out))))))
(def (owners)
  (list->hash-table
    (filter (lambda (entry)
              (ormap (lambda (prefix) (string-prefix? prefix (car entry)))
                     '("core/" "program/" "table/" "candidate/"
                       "t/performance/uf-reuse/")))
            (hash->list (artifact-sources)))))
(def (main library)
  (generate-contract!)
  (add-load-path! library)
  (let (sources (owners))
    (make '("table/storage" "program/initialization" "program/view-replay" "program/view-state" "program/evaluate"
            "t/performance/uf-reuse/reference-view-replay"
            "t/performance/uf-reuse/reference-view-state"
                        "t/performance/uf-reuse/reference-initialization"
            "t/performance/uf-reuse/reference-evaluate"
            "t/performance/uf-reuse/reference-storage"
            "t/performance/uf-reuse/fixture"
            "t/performance/uf-reuse/runner")
      srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
      build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (unless (artifact-matching-sources? sources (owners))
      (error "UF-REUSE execution owners changed during compilation"))))
