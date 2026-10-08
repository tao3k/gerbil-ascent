#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Build only. Upstream Gerbil owns test discovery and execution.
(import (only-in :gerbil/compiler compile-module compile-exe execute-pending-compile-jobs!)
        :gerbil/expander
        (only-in :std/make make)
        :std/os/flock :std/os/device
        (only-in "../t/native/artifact-admission.ss" artifact-main artifact-sources artifact-matching-sources? artifact-directory!)
        (only-in "../build.ss" gerbil-ascent-library-modules)
        (only-in :asp-gerbil-scheme/src/build-api/core-capacity initialize-native-build-core-capacity!))
(def test-cache (path-expand ".cache/ascent/native-library"))
(def (with-test-lane thunk)
  (artifact-directory! test-cache)
  (let (lock (open-output-file/lock (path-expand "lane.lock" test-cache) 120))
    (try (thunk) (finally (device-close lock)))))
(def performance-modules
  '("t/performance/ascent-scenario-performance-test.ss"
    "t/performance/ascent-binary-program-performance-test.ss"
    "t/performance/ascent-shortest-candidates-performance-test.ss"))
(def (qualification-files)
  ;; Allocation contracts require compiled production code. Source semantic
  ;; Suites remain in t/qualification; this native-only Case retains its bound.
  (append
   (map (lambda (name) (string-append "t/qualification/" name))
        (list-sort string<?
                   (filter (lambda (name) (string-suffix? "-test.ss" name))
                           (directory-files "t/qualification"))))
   '("t/performance/ascent-source-cut-allocation-test.ss"
     "t/performance/ascent-component-index-performance-test.ss"
     "t/performance/ascent-actor-credit-performance-test.ss"
     "t/performance/ascent-trrel-uf-performance-test.ss"
     "t/performance/ascent-steensgaard-performance-test.ss"
     "t/performance/ascent-relation-view-performance-test.ss"
     "t/performance/scheme-library-lifecycle-performance-test.ss")))

(def (prepare-test-library! (tests []))
  (let* ((library (path-expand "lib" test-cache))
         (module-file (path-expand "modules.sexp" test-cache))
         (modules (append gerbil-ascent-library-modules
                          '("t/performance/native-library" "t/performance/ascent-ss-profile"
                            "t/scenarios/performance/ascent-table-expression/baseline"
                            "t/native/artifact-admission" "t/model/response-projection")
                          (if (or (member "t/qualification/ascent-relation-view-test.ss" tests)
                                  (member "t/performance/ascent-relation-view-performance-test.ss" tests))
                            '("t/qualification/ascent-relation-view-fixture") [])
                          (if (member "t/qualification/ascent-callback-plan-test.ss" tests)
                            '("t/performance/callback-plan/expression-reference") [])
                          (if (member "t/qualification/ascent-expression-plan-test.ss" tests)
                            '("t/performance/expression-plan/reference"
                              "t/performance/expression-plan/analysis-reference"
                              "t/performance/expression-plan/planning-reference"
                              "t/performance/expression-plan/evaluate-reference"
                              "t/performance/expression-plan/input") [])
                          (if (member "t/qualification/ascent-proof-replay-test.ss" tests)
                            '("t/performance/proof-replay/reference") [])
                          (if (member "t/qualification/ascent-typed-domain-test.ss" tests)
                            '("t/performance/typed-domain/operator-reference" "t/performance/typed-domain/reference") [])
                          (if (member "t/qualification/ascent-nonmembership-index-test.ss" tests)
                            '("t/performance/nonmembership-index/reference" "t/performance/nonmembership-index/input") [])
                          (if (member "t/qualification/ascent-temporal-projection-test.ss" tests)
                            '("t/performance/temporal-projection/reference") [])
                          (if (member "t/qualification/ascent-uf-commit-test.ss" tests)
                            '("t/performance/uf-commit/reference") [])
                          (if (or (member "t/qualification/ascent-trrel-uf-test.ss" tests)
                                  (member "t/performance/ascent-trrel-uf-performance-test.ss" tests))
                            '("t/performance/trrel-uf/reference" "t/performance/trrel-uf/root-scan-reference") [])
                          ;; Compile the complete independent reference graph
                          ;; for both ordinary module tests and AOT linkage.
                          (if (member "t/qualification/ascent-index-entry-test.ss" tests)
                            '("t/performance/index-sharing/reference") [])
                          (if (member "t/qualification/ascent-index-lifecycle-test.ss" tests)
                            '("t/qualification/ascent-index-reference-funs"
                              "t/qualification/ascent-index-reference-provider"
                              "t/qualification/ascent-positive-plan-reference-analysis"
                              "t/qualification/ascent-index-reference-evaluate")
                            [])
                          (if (member "t/qualification/scheme-finite-mapping-test.ss" tests)
                            '("t/performance/finite-mapping/reference-types"
                              "t/performance/finite-mapping/reference-objects"
                              "t/performance/finite-mapping/reference")
                            [])
                          (if (member "t/qualification/scheme-provenance-graph-test.ss" tests)
                            '("t/performance/provenance-index/reference"
                              "t/performance/provenance-maintenance/reference")
                            [])
                          (if (member "t/qualification/scheme-bounded-datum-test.ss" tests)
                            '("t/performance/bounded-datum/reference")
                            [])
                          (if (or (member "t/qualification/ascent-actor-credit-test.ss" tests)
                                  (member "t/performance/ascent-actor-credit-performance-test.ss" tests))
                            '("t/performance/actor-credit/reference"
                              "t/performance/actor-credit/coordinator-reference"
                              "t/performance/actor-credit/fixture")
                            [])
                          (if (or (member "t/qualification/ascent-component-index-test.ss" tests)
                                  (member "t/performance/ascent-component-index-performance-test.ss" tests)
                                  (member "t/qualification/ascent-actor-credit-test.ss" tests)
                                  (member "t/performance/ascent-actor-credit-performance-test.ss" tests))
                            '("t/performance/component-index/reference"
                              "t/performance/component-index/coordinator-reference"
                              "t/performance/component-index/fixture")
                            [])
                          (if (member "t/qualification/ascent-positive-components-test.ss" tests)
                            '("t/performance/component-scope/reference"
                              "t/performance/component-scope/fixture")
                            [])
                          (if (member "t/qualification/ascent-strata-preflight-test.ss" tests)
                            '("t/performance/strata-preflight/reference-semantics"
                              "t/performance/strata-preflight/reference-planning"
                              "t/performance/strata-preflight/reference-evaluate"
                              "t/performance/strata-preflight/fixture")
                            [])
                          (if (member "t/qualification/ascent-index-build-test.ss" tests)
                            '("t/performance/index-build/reference-funs"
                              "t/performance/index-build/reference-access"
                              "t/performance/index-build/reference-index"
                              "t/performance/index-build/reference-evaluate"
                              "t/performance/index-build/fixture")
                            [])
                          (if (member "t/qualification/ascent-stratified-proof-test.ss" tests)
                            '("t/performance/stratified-model/reference-proof"
                              "t/performance/stratified-model/reference-producer")
                            [])
                          (if (member "t/qualification/ascent-source-log-test.ss" tests)
                            '("t/performance/source-log/reference-update-selection"
                              "t/performance/source-log/reference-reuse"
                              "t/performance/source-log/reference-evaluate"
                              "t/performance/source-log/reference-session"
                              "t/performance/source-log/fixture")
                            [])
                          (if (member "t/qualification/ascent-selected-activation-test.ss" tests)
                            '("t/performance/selected-activation/reference-selection"
                              "t/performance/selected-activation/reference-reuse"
                              "t/performance/selected-activation/reference-evaluate"
                              "t/performance/selected-activation/fixture")
                            [])
                          (if (member "t/qualification/ascent-storage-batch-test.ss" tests)
                            '("t/performance/storage-batch/reference"
                              "t/performance/storage-batch/reference-evaluate"
                              "t/performance/storage-batch/fixture")
                            [])
                          (if (or (member "t/qualification/ascent-relation-view-test.ss" tests)
                                  (member "t/qualification/ascent-index-entry-test.ss" tests)
                                  (member "t/qualification/ascent-component-index-test.ss" tests)
                                  (member "t/performance/ascent-component-index-performance-test.ss" tests)
                                  (member "t/performance/ascent-relation-view-performance-test.ss" tests))
                            '("t/performance/index-entry/reference"
                              "t/performance/index-entry/reference-evaluate"
                              "t/performance/index-entry/fixture")
                            [])
                          (if (member "t/qualification/ascent-rule-bindings-test.ss" tests)
                            '("t/performance/rule-bindings/reference"
                              "t/performance/rule-bindings/reference-positive"
                              "t/performance/rule-bindings/reference-evaluate"
                              "t/performance/rule-bindings/fixture")
                            [])
                          (if (member "t/qualification/scheme-finite-replay-test.ss" tests)
                            '("t/performance/finite-replay/reference-funs"
                              "t/performance/finite-replay/reference")
                            []))))
    ;; AOT links the complete fixture/reference closure. These support modules
    ;; previously resolved from source in gxtest; source loading is not a native
    ;; carrier dependency. Native make still owns dependency order/currentness.
    (let (support
          (map (lambda (name) (string-append "t/qualification/" (path-strip-extension name)))
               (list-sort string<?
                 (filter (lambda (name)
                           (and (string-suffix? ".ss" name)
                                (not (string-suffix? "-test.ss" name))))
                         (directory-files "t/qualification")))))
      (set! modules (append modules (filter (lambda (module) (not (member module modules))) support))))
    (call-with-output-file [path: module-file truncate: #t]
      (lambda (out) (write modules out) (newline out)))
    ;; Upstream make checks production, reference and consumer currentness.
    (add-load-path! library)
    (setenv "ASCENT_TEST_LIBRARY" library)
    (setenv "ASCENT_PERFORMANCE_MODULES" module-file)
    (setenv "GERBIL_LOADPATH"
      (string-append library ":" (current-directory) ":" (getenv "GERBIL_LOADPATH" "")))
    (let* ((consumers (map path-strip-extension tests))
           (all (append modules (filter (lambda (module) (not (member module modules))) consumers)))
           (started (current-jiffy))
           (sources (artifact-sources)))
      (displayln "BUILD-TEST-LIBRARY modules=" (length all)
                 " cores=" (initialize-native-build-core-capacity!))
      (force-output)
      ;; Upstream make owns dependency order, compiler threads and currentness.
      ;; The complete original Suite roster compiles in one gxi process.
      (make all srcdir: (current-directory) libdir: library
            build-deps: (path-expand "build-deps" test-cache))
      (unless (artifact-matching-sources? sources (artifact-sources))
        (error "source changed during test library compilation"))
      (displayln "BUILD-TEST-LIBRARY-OK wall-seconds="
                 (exact->inexact (/ (- (current-jiffy) started) (jiffies-per-second))))
      (force-output))))
(def (main . args)
  (match args
    (["library"] (with-test-lane (lambda () (prepare-test-library! (append (qualification-files) performance-modules)))))
    (["dsl"]
     (with-test-lane
      (lambda ()
        ;; Freeze and bind under the same compilation lock: concurrent builds
        ;; cannot replace each other's source snapshot.
        (artifact-main "freeze")
        (prepare-test-library!
         '("t/qualification/scheme-closure-contract-test.ss"
           "t/qualification/scheme-artifact-test.ss"
           "t/qualification/scheme-provenance-graph-test.ss"
           "t/qualification/scheme-higher-order-test.ss"
           "t/qualification/ascent-index-lifecycle-test.ss"
           "t/qualification/scheme-finite-mapping-test.ss"
    "t/qualification/scheme-session-deletion-test.ss"
    "t/qualification/ascent-timeout-test.ss"
    "t/qualification/scheme-stratified-provenance-test.ss"
    "t/qualification/scheme-model-closure-test.ss"
           "t/qualification/scheme-operator-test.ss"
           "t/qualification/scheme-library-contract-test.ss"
           "t/qualification/scheme-operator-retained-test.ss"
           "t/qualification/ascent-finite-evidence-test.ss"
           "t/qualification/ascent-positive-nonmembership-test.ss"
           "t/qualification/ascent-byods-lattice-fixture.ss"
           "t/qualification/ascent-session-corpus.ss"
           "t/qualification/ascent-byods-session-output.ss"
           "t/qualification/ascent-multi-source-session-output.ss"
           "t/qualification/ascent-grouped-eqrel-session-output.ss"
           "t/qualification/ascent-byods-lattice-session-output.ss"
           "t/qualification/ascent-arity-repetition-output.ss"
           "t/qualification/ascent-eqrel-program-output.ss"
           "t/qualification/ascent-byods-query-output.ss"
           "tools/model-source-closure.ss"))
        ;; Output-dir precedence binds the executable to this current Library,
        ;; even when GERBIL_PATH also contains an older installed ASCENT.
        (let ((source "t/model/study.ss")
              (options [output-dir: (path-expand "lib" test-cache)
                        output-file: (path-expand "dsl-closure" test-cache)
                        parallel: #t verbose: #t invoke-gsc: #t static: #t]))
          ;; This lane owns the static cache. timeout terminates the previous
          ;; build process group, but gxc's existence-based object locks can
          ;; survive SIGTERM. Recover only this lane's object locks, never
          ;; dependency-prefix locks or the advisory lane lock.
          (let (static-dir (path-expand "lib/static" test-cache))
            (when (file-exists? static-dir)
              (for-each
               (lambda (name)
                 (when (string-suffix? ".o.lock" name)
                   (displayln "RECOVER-OBJECT-LOCK " name)
                   (delete-file (path-expand name static-dir))))
               (directory-files static-dir))))
          ;; gxc also locks the executable stub in the cache root. These two
          ;; exact paths belong to this entry, not another compiler or prefix.
          (for-each
           (lambda (name)
             (let (path (path-expand name test-cache))
               (when (file-exists? path)
                 (displayln "RECOVER-ENTRY-OBJECT-LOCK " name)
                 (delete-file path))))
           '("dsl-closure__exe.o.lock" "dsl-closure__exe_.o.lock"))
          ;; An old executable must never survive a no-op/failed compilation.
          (let (binary (path-expand "dsl-closure" test-cache))
            (when (file-exists? binary) (delete-file binary)))
          (compile-module source [invoke-gsc: #f options ...])
          (compile-exe source options)
          ;; Drain every queued object and the compiler's link barrier before
          ;; binding. Compiler exceptions propagate; no partial binary qualifies.
          (execute-pending-compile-jobs!)
          (artifact-main "bind")))))
    (else (error "invalid test library build mode" args))))
