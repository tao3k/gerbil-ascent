#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/build-script defbuild-script)
        (only-in :std/make make)
        :std/misc/process :std/os/flock :std/os/device
        (only-in :asp-gerbil-scheme/src/build-api/core-capacity
                 initialize-native-build-core-capacity!)
        (only-in :asp-gerbil-scheme/building-api
                 asp-gerbil-scheme-package-spec!
                 asp-gerbil-scheme-library-package-prototype))

(def gerbil-ascent-library-modules
  '("table/expression"
    "table/funs"
    "table/eqrel"
    "table/trrel"
    "table/provider"
    "table/access"
    "table/storage"
    "table/interface"
    "program/types"
    "program/objects"
    "program/aggregators"
    "program/syntax"
    "program/planning"
    "program/positive"
    "program/scheme-checked"
    "program/scheme-admission"
    "program/scheme-language"
    "program/operator"
    "program/operator-change"
    "program/operator-session"
    "program/graph"
    "program/funs"
    "program/analysis"
    "program/summary"
    "program/admission"
    "program/result"
    "program/evaluate"
    "program/session"
    "program/interface"
    "core/binary-program"
    "candidate/closure"
    "candidate/types"
    "candidate/program"
    "candidate/funs"
    "candidate/provenance"
    "candidate/nonmembership"
    "candidate/finite-evidence"
    "candidate/stratified-proof"
    "candidate/stratified-producer"
    "candidate/reasoning"
    "temporal/lens"
    "interface/request"))

(asp-gerbil-scheme-package-spec!
 (gerbil-ascent-library-package-spec
  @ asp-gerbil-scheme-library-package-prototype)
 (spec gerbil-ascent-build-spec)
 (modules gerbil-ascent-library-modules))

;; Build and test selection belong to the package entrypoint. std/make owns
;; compilation/currentness; gxtest owns Suites, Cases, setup and cleanup.
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
    "t/qualification/scheme-library-contract-test.ss"
    "t/qualification/scheme-native-integration-test.ss"
    "t/qualification/scheme-native-language-test.ss"
    "t/qualification/scheme-native-reduction-test.ss"
    "t/qualification/scheme-operator-retained-test.ss"
    "t/qualification/scheme-operator-test.ss"
    "t/qualification/scheme-relational-test.ss"))

(defbuild-script (gerbil-ascent-build-spec))
(def compile-main main)
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
                          '("t/scenarios/performance/ascent-table-expression/baseline"))))
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
(set! main
  (lambda args
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
      (["meta"] (compile-main "meta"))
      (["spec"] (compile-main "spec"))
      (else (with-test-lane (lambda () (apply compile-main args)))))
    (exit command-exit-status)))
