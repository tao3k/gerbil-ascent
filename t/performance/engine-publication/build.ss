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
             (targetRationale . "Complete retained execution and result publication")
             (allocationSampleCount . 5) (baseline . "07c03062b417a95c09e0aadb80b7bc9249fd8102")
             (scenarios (wide 9/10 0 16) (dirty 9/10 0 16)
                        (cold 11/10 1/50000 0) (duplicate 11/10 1/50000 0)
                        (small 11/10 1/50000 0) (fresh 11/10 1/50000 0))
             (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-ENGINE-PUBLICATION 'engine-publication
                 "Retained execution commits and ordered result publication"
                 "Wide and medium changed cuts with duplicate, cold, small and fresh controls"
                 "Exact incremental sizes and complete demanded row sequences"
                 '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base)))
         (path "t/performance/engine-publication/benchmark.ss"))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid engine publication fixture"))
    (unless (and (file-exists? path) (equal? contract (call-with-input-file path read)))
      (call-with-output-file [path: path truncate: #t]
        (lambda (out) (write contract out) (newline out))))))
(def (owners)
  (list->hash-table
    (filter (lambda (entry)
              (ormap (lambda (prefix) (string-prefix? prefix (car entry)))
                     '("core/" "program/" "table/" "candidate/"
                       "t/performance/engine-publication/")))
            (hash->list (artifact-sources)))))
(def (main library)
  (generate-contract!)
  (add-load-path! library)
  (let (sources (owners))
    (make '("program/result" "program/execution-publication" "program/evaluate" "t/performance/engine-publication/reference-result"
            "t/performance/engine-publication/reference"
            "t/performance/engine-publication/fixture"
            "t/performance/engine-publication/runner")
      srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
      build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (unless (artifact-matching-sources? sources (owners))
      (error "engine publication owners changed during compilation"))))
