;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander :gerbil/compiler :std/make
        (only-in :asp-gerbil-scheme/benchmark-api make-benchmark-fixture benchmark-fixture-contract-pass?)
        (only-in :gerbil-ascent/t/native/artifact-admission artifact-sources artifact-matching-sources?))
(export main)
;;; Generate the checked benchmark datum through ASP's native fixture API.
;;; These explicit settings preserve the gates fixed before the first sample.
(def (generate-contract!)
  (let* ((settings
           '((max_total . 999ms) (target_total . 500ms) (regression_budget . 499ms)
             (expected_over_input_budget . 0ms)
             (targetRationale . "Complete Operator Program and Fragment construction and publication")
             (allocationSampleCount . 5) (baseline . "652934cd728d7edee32df020af75e9632dffc755")
             (scenarios (program 9/10 0 16) (fragment 9/10 0 16)
                        (cold 11/10 1/50000 0) (custom 11/10 1/50000 0)
                        (small 11/10 1/50000 0) (empty 11/10 1/50000 0))
             (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-OPERATOR-PUBLICATION 'operator-publication
                 "Canonical constructor applicability and complete root admission"
                 "Wide mixed operator graph with lexical fix, custom receiver and cold solve controls"
                 "Alpha-normalized complete declarations and independent singleton set truth"
                 '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base)))
         (path "t/performance/operator-publication/benchmark.ss"))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid Operator publication fixture"))
    (unless (and (file-exists? path) (equal? contract (call-with-input-file path read)))
      (call-with-output-file [path: path truncate: #t]
        (lambda (out) (write contract out) (newline out))))))
(def (owners)
  (list->hash-table
    (filter (lambda (entry)
              (ormap (lambda (prefix) (string-prefix? prefix (car entry)))
                     '("core/" "program/" "table/"
                       "t/performance/operator-publication/")))
            (hash->list (artifact-sources)))))
(def (main library (binary #f))
  (generate-contract!)
  (add-load-path! library)
  (let (sources (owners))
    (make (append '("program/types" "program/objects" "program/operator" "t/performance/operator-publication/reference"
                    "t/performance/operator-publication/fixture")
                  (if binary '("t/performance/operator-publication/runner") []))
      srcdir: (current-directory) libdir: library parallelize: (##cpu-count)
      build-deps: (path-expand ".cache/ascent/native-library/build-deps"))
    (when binary
      (compile-exe "t/performance/operator-publication/runner.ss"
        [output-dir: library output-file: binary parallel: #t
         verbose: #t invoke-gsc: #t static: #t])
      (execute-pending-compile-jobs!))
    (unless (artifact-matching-sources? sources (owners))
      (error "operator publication owners changed during compilation"))))
