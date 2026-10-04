#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Test compilation and scheduling belong to t/. std/make owns native
;;; currentness and gxtest owns Suites and Cases.
(import (only-in :gerbil/compiler compile-module compile-exe execute-pending-compile-jobs!)
        (only-in :std/make make)
        :std/misc/process :std/os/flock :std/os/device
        (only-in "artifact.ss" artifact-main)
        (only-in "../../build.ss" gerbil-ascent-library-modules)
        (only-in :asp-gerbil-scheme/src/build-api/core-capacity
                 initialize-native-build-core-capacity!))

;; The 64-cut retained-operator stress module uses the exclusive lane to keep
;; its original process deadline isolated from the module pool's CPU load.
(def parallel-modules
  '("t/qualification/ascent-aggregate-program-test.ss"
    "t/qualification/ascent-binary-program-test.ss"
    "t/qualification/ascent-binding-program-test.ss"
    "t/qualification/ascent-binding-test.ss"
    "t/qualification/ascent-byods-index-test.ss"
    "t/qualification/ascent-byods-invariants-test.ss"
    "t/qualification/ascent-candidate-description-test.ss"
    "t/qualification/ascent-closure-candidates-test.ss"
    "t/qualification/ascent-contract-union-test.ss"
    "t/qualification/ascent-declaration-scope-test.ss"
    "t/qualification/ascent-eqrel-program-test.ss"
    "t/qualification/ascent-finite-evidence-test.ss"
    "t/qualification/ascent-index-lifecycle-test.ss"
    "t/qualification/ascent-index-program-test.ss"
    "t/qualification/ascent-invalid-program-test.ss"
    "t/qualification/ascent-lattice-program-test.ss"
    "t/qualification/ascent-materialization-test.ss"
    "t/qualification/ascent-module-program-test.ss"
    "t/qualification/ascent-multi-frontier-test.ss"
    "t/qualification/ascent-poo-primitives-test.ss"
    "t/qualification/ascent-positive-nonmembership-test.ss"
    "t/qualification/ascent-positive-plan-test.ss"
    "t/qualification/ascent-positive-provenance-test.ss"
    "t/qualification/ascent-reasoning-library-test.ss"
    "t/qualification/ascent-request-projection-test.ss"
    "t/qualification/ascent-result-publication-test.ss"
    "t/qualification/ascent-scc-summary-test.ss"
    "t/qualification/ascent-set-batch-test.ss"
    "t/qualification/ascent-set-emit-test.ss"
    "t/qualification/ascent-set-size-test.ss"
    "t/qualification/ascent-set-source-test.ss"
    "t/qualification/ascent-size-test.ss"
    "t/qualification/ascent-source-admission-test.ss"
    "t/qualification/ascent-strata-test.ss"
    "t/qualification/ascent-stratified-proof-test.ss"
    "t/qualification/ascent-syntax-test.ss"
    "t/qualification/ascent-table-expression-test.ss"
    "t/qualification/ascent-temporal-lens-test.ss"
    "t/qualification/ascent-timeout-test.ss"
    "t/qualification/ascent-timing-test.ss"
    "t/qualification/ascent-workspace-test.ss"
    "t/qualification/scheme-closure-contract-test.ss"
    "t/qualification/scheme-provenance-graph-test.ss"
    "t/qualification/scheme-higher-order-test.ss"
    "t/qualification/scheme-session-deletion-test.ss"
    "t/qualification/scheme-stratified-provenance-test.ss"
    "t/qualification/scheme-model-closure-test.ss"
    "t/qualification/scheme-library-contract-test.ss"
    "t/qualification/scheme-native-integration-test.ss"
    "t/qualification/scheme-native-language-test.ss"
    "t/qualification/scheme-native-reduction-test.ss"
    "t/qualification/scheme-operator-test.ss"
    "t/qualification/scheme-relational-test.ss"))

(def command-exit-status 0)
(def (run-command command)
  (run-process command stderr-redirection: #t
    check-status: (lambda (raw settings)
      (set! command-exit-status
            (if (zero? (bitwise-and raw #xff))
              (quotient raw 256) (+ 128 (bitwise-and raw #xff)))))
    coprocess: (lambda (process)
      (let loop ()
        (let (line (read-line process))
          (unless (eof-object? line)
            (displayln line) (force-output) (loop)))))))
(def test-cache (path-expand ".cache/ascent/native-library"))
(def (with-test-lane thunk)
  (run-process/batch ["mkdir" "-p" test-cache])
  ;; One package invocation owns the lane; its module children do not relock.
  (let (lock (open-output-file/lock (path-expand "lane.lock" test-cache) 120))
    (try (thunk) (finally (device-close lock)))))
(def quick-modules
  '("t/qualification/ascent-finite-evidence-test.ss"
    "t/qualification/ascent-positive-nonmembership-test.ss"
    "t/qualification/ascent-positive-provenance-test.ss"
    "t/qualification/ascent-reasoning-library-test.ss"
    "t/qualification/ascent-stratified-proof-test.ss"))
(def performance-modules
  '("t/performance/ascent-scenario-performance-test.ss"
    "t/performance/ascent-binary-program-performance-test.ss"
    "t/performance/ascent-shortest-candidates-performance-test.ss"))
(def (qualification-files)
  (map (lambda (name) (string-append "t/qualification/" name))
       (list-sort string<?
                  (filter (lambda (name) (string-suffix? "-test.ss" name))
                          (directory-files "t/qualification")))))
(def (prepare-test-library! (tests []))
  (let* ((library (path-expand "lib" test-cache))
         (module-file (path-expand "modules.sexp" test-cache))
         (modules (append gerbil-ascent-library-modules
                          '("t/scenarios/performance/ascent-table-expression/baseline"
                            "t/harness/artifact" "t/harness/prediction"))))
    (call-with-output-file [path: module-file truncate: #t]
      (lambda (out) (write modules out) (newline out)))
    ;; Compile both sides of the paired performance fixture. Native make also
    ;; performs the incremental dependency check on every test invocation.
    (make (append modules (map path-strip-extension tests)) srcdir: (current-directory) libdir: library
          build-deps: (path-expand "build-deps" test-cache))
    (force-output)
    (setenv "ASCENT_TEST_LIBRARY" library)
    (setenv "ASCENT_PERFORMANCE_MODULES" module-file)
    (setenv "GERBIL_LOADPATH"
            (string-append library ":" (current-directory) ":" (getenv "GERBIL_LOADPATH" "")))))
(def (main . args)
  (match args
    (["test-jobs" value]
     (let (jobs (if (equal? value "auto")
                 (initialize-native-build-core-capacity!) (string->number value)))
       (unless (and (integer? jobs) (> jobs 0)) (error "invalid test jobs" value))
       (displayln (inexact->exact jobs))))
    (["test-modules" "quick"] (for-each displayln quick-modules))
    (["test-modules" lane]
     (unless (member lane '("parallel" "exclusive")) (error "invalid test lane" lane))
     (for-each
      (lambda (name)
        (let (path (string-append "t/qualification/" name))
          (when (and (string-suffix? "-test.ss" name)
                     (eq? (and (member path parallel-modules) #t) (equal? lane "parallel")))
            (displayln path))))
      (list-sort string<? (directory-files "t/qualification"))))
    (["run" "--" . command]
     (with-test-lane (lambda () (run-command command))))
    (["test" jobs lane]
     (with-test-lane
      (lambda () (prepare-test-library! (qualification-files))
                 (run-command ["just" "_test-suite" jobs lane]))))
    (["test-quick"]
     (with-test-lane
      (lambda () (prepare-test-library! quick-modules)
                 (run-command ["just" "_test-quick"]))))
    (["build-dsl-closure"]
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
           "tools/model-source-closure.ss"))
        ;; Output-dir precedence binds the executable to this current Library,
        ;; even when GERBIL_PATH also contains an older installed ASCENT.
        (let ((source "t/harness/dsl-closure.ss")
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
    (["test-file" path]
     (with-test-lane
      (lambda () (prepare-test-library! [path])
                 (run-command ["just" "_test-file" path]))))
    (["performance" name]
     (with-test-lane
      (lambda () (prepare-test-library! performance-modules)
                 (run-command (if (equal? name "suite")
                                      ["just" "_performance"]
                                      ["just" "_performance-scenario" name])))))
    (else (error "invalid ASCENT test command" args)))
  (exit command-exit-status))
