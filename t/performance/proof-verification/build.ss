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
             (targetRationale . "Complete positive proof DAG verification")
             (allocationSampleCount . 5) (baseline . "7bb4ba0cfe372357d5a30cef644407fb77582a57")
             (scenarios (wide 9/10 0 16) (mixed 9/10 0 16)
                        (cold 11/10 1/50000 0) (forged 11/10 1/50000 0)
                        (small 11/10 1/50000 0) (source 11/10 1/50000 0))
             (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-PROOF-VERIFICATION 'proof-verification
                 "Invocation-local rule replay and complete predecessor admission"
                 "Wide bindings and scalar clauses with cold producer and forged proof controls"
                 "Complete independent node replay and fixed expected verdicts"
                 '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base)))
         (path "t/performance/proof-verification/benchmark.ss"))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid Operator publication fixture"))
    (unless (and (file-exists? path) (equal? contract (call-with-input-file path read)))
      (call-with-output-file [path: path truncate: #t]
        (lambda (out) (write contract out) (newline out))))))
(def (owners)
  (list->hash-table
    (filter (lambda (entry)
              (ormap (lambda (prefix) (string-prefix? prefix (car entry)))
                     '("core/" "program/" "table/" "candidate/"
                       "t/performance/proof-verification/")))
            (hash->list (artifact-sources)))))
(def (main library)
  (generate-contract!)
  (add-load-path! library)
  (let (sources (owners))
    (make '("candidate/proof-frame" "candidate/provenance"
            "t/performance/proof-verification/reference"
            "t/performance/proof-verification/fixture"
            "t/performance/proof-verification/runner")
      srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
      build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (unless (artifact-matching-sources? sources (owners))
      (error "proof verification owners changed during compilation"))))
