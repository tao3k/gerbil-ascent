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
             (targetRationale . "Complete frozen view publication and ordered export")
             (allocationSampleCount . 5) (baseline . "3cfbb1a7e17beb98097510a07cecf2a9b2478284")
             (scenarios (eqrel 9/10 0 16) (grouped 9/10 0 16) (retained 9/10 0 16)
                        (cold 11/10 1/50000 0) (small 11/10 1/50000 0)
                        (uf 11/10 1/50000 0) (derived 11/10 1/50000 0) (native 11/10 1/50000 0))
             (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-VIEW-EXPORT-EXECUTION 'view-export
                 "Complete view publication and ordered exports"
                 "EqRel grouped and retained exports with UF cold small and derived controls"
                 "Complete relation sizes and independent closure truth"
                 '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base)))
         (path "t/performance/view-export/benchmark.ss"))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid VIEW-EXPORT execution fixture"))
    (unless (and (file-exists? path) (equal? contract (call-with-input-file path read)))
      (call-with-output-file [path: path truncate: #t]
        (lambda (out) (write contract out) (newline out))))))
(def (owners)
  (list->hash-table
    (filter (lambda (entry)
              (ormap (lambda (prefix) (string-prefix? prefix (car entry)))
                     '("core/" "program/" "table/" "candidate/"
                       "t/performance/view-export/")))
            (hash->list (artifact-sources)))))
(def (main library)
  (generate-contract!)
  (add-load-path! library)
  (let (sources (owners))
    (make '("table/eqrel" "program/view-state" "program/evaluate"
            "t/performance/view-export/reference-eqrel"
            "t/performance/view-export/reference-view-state"
            "t/performance/view-export/reference-evaluate"
            "t/performance/view-export/fixture"
            "t/performance/view-export/runner")
      srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
      build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (unless (artifact-matching-sources? sources (owners))
      (error "VIEW-EXPORT execution owners changed during compilation"))))
