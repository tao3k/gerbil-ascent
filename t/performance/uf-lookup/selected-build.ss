;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/make :asp-gerbil-scheme/benchmark-api
        (only-in :asp-gerbil-scheme/src/build-api/core-capacity initialize-native-build-core-capacity!)
        (only-in :std/misc/process run-process)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :std/string/misc string-subst)
        (only-in :gerbil-ascent/t/native/artifact-admission artifact-digest artifact-directory!)
        :std/encoding/json)
(export main selected-contract)

(def baseline "268e89b84c487696d5fbf032a10d6dd39479e10a")
(def inputs
  '("gerbil.pkg" "core/relation-view.ss" "table/trrel-uf.ss"
    "t/performance/uf-lookup/fixture.ss" "t/performance/uf-lookup/runner.ss"
    "t/performance/uf-lookup/selected-build.ss"))

;; A fixed experiment contract is a value. Preparing it never rewrites the
;; historical lookup contract or runs that study's builder first.
(def (selected-contract)
  (let* ((settings
          '((max_total . 999ms) (target_total . 500ms) (regression_budget . 499ms)
            (expected_over_input_budget . 0ms)
            (targetRationale . "Owned selected product collection across left right and grouped queries")
            (allocationSampleCount . 5) (trajectoriesPerSample . 4096)
            (allocationBatchSize . 256)
            (baseline . "268e89b84c487696d5fbf032a10d6dd39479e10a")
            (allocationTargets) (targetAllocationRatio . 4/5)
            (scenarios (complete 9/10 0 16) (union 11/10 1/50000 0)
                       (absent 11/10 1/50000 0) (small 11/10 1/50000 0))
            (allocationRatio . 11/10) (allocationOverheadBytes . 8192)))
         (base (make-benchmark-fixture 'ASCENT-UF-LOOKUP-EXECUTION 'uf-lookup
                 "Complete selected UF query workflow"
                 "4096 identical left right grouped query workflows and fixed controls"
                 "Independent Cartesian closure truth and exact ordered rows" '(native paired semantics)))
         (contract (append settings (filter (lambda (entry) (not (assq (car entry) settings))) base))))
    (unless (benchmark-fixture-contract-pass? contract) (error "invalid selected UF contract"))
    contract))

(def (write-source! path text)
  (artifact-directory! (path-directory path))
  (call-with-output-file [path: path truncate: #t]
    (lambda (out) (display text out))))

(def (reference! source directory expected)
  (let (target (path-expand (string-append "baseline/" source) directory))
    (write-source! target (run-process ["git" "show" (string-append baseline ":" source)]))
    (unless (equal? expected (artifact-digest target))
      (error "UF baseline source identity differs" source))
    (call-with-input-file target read-all-as-string)))

(def (main directory dependencies)
  (let* ((root (current-directory))
         (directory (path-expand directory))
         (source (path-expand "source" directory))
         (library (path-expand "lib" directory))
         (imports (path-expand "imports" directory))
         (before (map (lambda (input) (cons input (artifact-digest input))) inputs)))
    (when (file-exists? source) (error "study output already exists" directory))
    (for-each (lambda (input)
      (let (target (path-expand input source))
        (artifact-directory! (path-directory target))
        (copy-file input target))) inputs)
    (let ((view (reference! "core/relation-view.ss" directory
                  "d996655ee37c58abcde6a40b157eceffcf9aba860c9f60c0acf9e9ec12e2c995"))
          (uf (reference! "table/trrel-uf.ss" directory
                "9583ec273e78ffa1cfb2f2e74a66da514494081603afebbe5974a78265cfaa63")))
      (write-source! (path-expand "t/performance/uf-lookup/reference-relation-view.ss" source) view)
      (write-source! (path-expand "t/performance/uf-lookup/reference-trrel-uf.ss" source)
        (string-subst uf ":gerbil-ascent/core/relation-view"
          ":gerbil-ascent/t/performance/uf-lookup/reference-relation-view")))
    (artifact-directory! library)
    (artifact-directory! imports)
    (artifact-directory! (path-expand "receipts" directory))
    (create-symbolic-link source (path-expand "gerbil-ascent" imports))
    (setenv "GERBIL_LOADPATH"
      (string-append library ":" imports ":" dependencies ":" (getenv "GERBIL_LOADPATH" "")))
    (add-load-path! imports)
    (add-load-path! library)
    (initialize-native-build-core-capacity!)
    (current-directory source)
    (make '("core/relation-view" "table/trrel-uf"
            "t/performance/uf-lookup/reference-relation-view"
            "t/performance/uf-lookup/reference-trrel-uf"
            "t/performance/uf-lookup/fixture" "t/performance/uf-lookup/runner")
      srcdir: source libdir: library build-deps: (path-expand "build-deps" directory))
    (for-each (lambda (entry)
      (unless (and (equal? (cdr entry) (artifact-digest (path-expand (car entry) root)))
                   (equal? (cdr entry) (artifact-digest (path-expand (car entry) source))))
        (error "UF study input changed during preparation" (car entry)))) before)
    (call-with-output-file (path-expand "contract.sexp" directory)
      (lambda (out) (write (selected-contract) out) (newline out)))
    (call-with-output-file (path-expand "inputs.json" directory)
      (lambda (out)
        (display (json->string
          (hash ("baseline" baseline) ("candidateInputs" (list->hash-table before))
                ("referenceView" (artifact-digest "t/performance/uf-lookup/reference-relation-view.ss"))
                ("referenceUF" (artifact-digest "t/performance/uf-lookup/reference-trrel-uf.ss")))) out)
        (newline out)))))
