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
             (targetRationale . "Complete founded stratified proof production and verification")
             (allocationSampleCount . 5) (baseline . "97e41652d7787ee8063a2388e593e893be8d2449")
             (scenarios (wide 9/10 0 16) (produce 9/10 0 16)
                        (cold 11/10 1/50000 0) (forged 11/10 1/50000 0)
                        (small 11/10 1/50000 0) (source 11/10 1/50000 0))
             (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-STRATIFIED-REPLAY 'stratified-replay
                 "Invocation-local rule replay and complete predecessor admission"
                 "Wide sum groups with cold producer, forged, small and source controls"
                 "Complete independent node replay and fixed expected verdicts"
                 '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base)))
         (path "t/performance/stratified-replay/benchmark.ss"))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid stratified replay fixture"))
    (unless (and (file-exists? path) (equal? contract (call-with-input-file path read)))
      (call-with-output-file [path: path truncate: #t]
        (lambda (out) (write contract out) (newline out))))))
(def (owners)
  (list->hash-table
    (filter (lambda (entry)
              (ormap (lambda (prefix) (string-prefix? prefix (car entry)))
                     '("core/" "program/" "table/" "candidate/"
                       "t/performance/stratified-replay/")))
            (hash->list (artifact-sources)))))
(def (main library)
  (generate-contract!)
  (add-load-path! library)
  (let (sources (owners))
    (make '("candidate/reduction-plan" "candidate/finite-plan" "candidate/finite-evidence" "candidate/stratified-plan" "candidate/stratified-proof" "candidate/stratified-producer"
            "t/performance/stratified-replay/reference-finite-plan" "t/performance/stratified-replay/reference-finite"
            "t/performance/stratified-replay/reference-proof" "t/performance/stratified-replay/reference-producer"
            "t/performance/stratified-replay/fixture"
            "t/performance/stratified-replay/runner")
      srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
      build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (unless (artifact-matching-sources? sources (owners))
      (error "stratified replay owners changed during compilation"))))
