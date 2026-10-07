;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; AOT entry for the known DSL discriminator. std/test owns every Case,
;;; verdict and marker; the entry adds no evaluator or expectation model.
(import (only-in :std/test/base TestModule TestHarness TestConfig
                 test-run! test-result-ok?)
        (only-in :gerbil-ascent/t/qualification/scheme-closure-contract-test
                 scheme-closure-contract-test))
(import (only-in :gerbil-ascent/t/qualification/scheme-operator-test scheme-operator-test)
        (only-in :gerbil-ascent/t/qualification/scheme-library-contract-test scheme-library-contract-test)
        (only-in :gerbil-ascent/t/qualification/scheme-operator-retained-test scheme-operator-retained-test)
        (only-in :gerbil-ascent/t/qualification/ascent-finite-evidence-test ascent-finite-evidence-test)
        (only-in :gerbil-ascent/t/qualification/ascent-positive-nonmembership-test ascent-positive-nonmembership-test))
(export main)
(import (only-in :gerbil-ascent/t/native/artifact-admission artifact-main))
(import (only-in :gerbil-ascent/t/qualification/scheme-artifact-test scheme-artifact-test))
(import (only-in :gerbil-ascent/t/model/response-projection prediction-main))
(import (only-in :gerbil-ascent/t/qualification/ascent-timeout-test ascent-timeout-test))

(import (only-in :gerbil-ascent/t/qualification/scheme-provenance-graph-test
                 scheme-provenance-graph-test))

(import (only-in :gerbil-ascent/t/qualification/scheme-higher-order-test
                 scheme-higher-order-test))

(import (only-in :gerbil-ascent/t/qualification/ascent-index-lifecycle-test
                 ascent-index-lifecycle-test))

(import (only-in :gerbil-ascent/t/qualification/scheme-finite-mapping-test
                 scheme-finite-mapping-test))

(import (only-in :gerbil-ascent/t/qualification/scheme-session-deletion-test
                 scheme-session-deletion-test session-benefit-main))

(import (only-in :gerbil-ascent/t/qualification/scheme-stratified-provenance-test
                 scheme-stratified-provenance-test))

(import (only-in :gerbil-ascent/t/qualification/scheme-model-closure-test
                 scheme-model-closure-test model-closure-compute model-closure-score))


;;; These are the unchanged Rust differential fixtures, compiled into the
;;; native entry. The command transports stdin/rows; fixture semantics stay
;;; Scheme-owned and Rust still checks every original expected row.
(import (only-in (rename-in :gerbil-ascent/t/qualification/ascent-byods-session-output (main byods-session-main)) byods-session-main))
(import (only-in (rename-in :gerbil-ascent/t/qualification/ascent-steensgaard-output (main steensgaard-main)) steensgaard-main))
(import (only-in (rename-in :gerbil-ascent/t/qualification/ascent-multi-source-session-output (main multi-source-session-main)) multi-source-session-main))
(import (only-in (rename-in :gerbil-ascent/t/qualification/ascent-grouped-eqrel-session-output (main grouped-eqrel-session-main)) grouped-eqrel-session-main))
(import (only-in (rename-in :gerbil-ascent/t/qualification/ascent-byods-lattice-session-output (main byods-lattice-session-main)) byods-lattice-session-main))
(import (only-in (rename-in :gerbil-ascent/t/qualification/ascent-arity-repetition-output (main arity-repetition-main)) arity-repetition-main))
(import (only-in (rename-in :gerbil-ascent/t/qualification/ascent-eqrel-program-output
                           (main eqrel-program-main)) eqrel-program-main))
(import (only-in (rename-in :gerbil-ascent/t/qualification/ascent-byods-query-output
                           (main byods-query-main)) byods-query-main))
(import (only-in (rename-in :gerbil-ascent/tools/model-source-closure
                           (main source-closure-main)) source-closure-main))

(def (check-native-oracle!)
  ;; Keep row stdout unchanged while reporting actual artifact admission.
  (parameterize ((current-output-port (current-error-port)))
    (with-catch
     (lambda (failure)
       (displayln "DSL-ARTIFACT-REJECTED " failure)
       (force-output)
       (exit 1))
     (lambda () (artifact-main "check")))))

(def (main . args)
  (match args
    (["--oracle" "eqrel-program" . flags]
     (check-native-oracle!)
     (apply eqrel-program-main flags)
     (exit 0))
    (["--retained-benefit"] (session-benefit-main) (exit 0))
    (["--source-closure" . roots] (apply source-closure-main roots) (exit 0))
    (["--oracle" name]
     (check-native-oracle!)
     (case (string->symbol name)
       ((byods-query) (byods-query-main))
       ((byods-session) (byods-session-main))
       ((steensgaard) (steensgaard-main))
       ((multi-source-session) (multi-source-session-main))
       ((grouped-eqrel-session) (grouped-eqrel-session-main))
       ((byods-lattice-session) (byods-lattice-session-main))
       ((arity-repetition) (arity-repetition-main))
       (else (error "unknown native differential fixture" name)))
     (exit 0))
    (["--oracle" "steensgaard" directory output-path]
     (check-native-oracle!)
     (steensgaard-main directory output-path) (exit 0))
    (["--study-compute" id] (model-closure-compute id) (exit 0))
    (["--study-project" path] (prediction-main path) (exit 0))
    (["--study-score" id path] (model-closure-score id path) (exit 0))
    (else (run-suites args))))

(def (run-suites args)
  (let* ((entries
          (list
                (cons "t/qualification/scheme-closure-contract-test.ss" scheme-closure-contract-test)
                (cons "t/qualification/scheme-artifact-test.ss" scheme-artifact-test)
                (cons "t/qualification/scheme-provenance-graph-test.ss" scheme-provenance-graph-test)
                (cons "t/qualification/scheme-higher-order-test.ss" scheme-higher-order-test)
                (cons "t/qualification/ascent-index-lifecycle-test.ss" ascent-index-lifecycle-test)
                (cons "t/qualification/scheme-finite-mapping-test.ss" scheme-finite-mapping-test)
                (cons "t/qualification/scheme-session-deletion-test.ss" scheme-session-deletion-test)
                (cons "t/qualification/ascent-timeout-test.ss" ascent-timeout-test)
                (cons "t/qualification/scheme-stratified-provenance-test.ss" scheme-stratified-provenance-test)
                (cons "t/qualification/scheme-model-closure-test.ss" scheme-model-closure-test)
                (cons "t/qualification/scheme-operator-test.ss" scheme-operator-test)
                (cons "t/qualification/scheme-library-contract-test.ss" scheme-library-contract-test)
                (cons "t/qualification/scheme-operator-retained-test.ss" scheme-operator-retained-test)
                (cons "t/qualification/ascent-finite-evidence-test.ss" ascent-finite-evidence-test)
                (cons "t/qualification/ascent-positive-nonmembership-test.ss" ascent-positive-nonmembership-test)))
         (selected (match args
                     ([] entries)
                     ([name]
                      (let (found (assoc name entries))
                        (unless found (error "unknown DSL Suite" name))
                        (list found)))
                     (_ (error "expected one known Suite path" args))))
         (modules
          (map (lambda (entry)
                 (TestModule (car entry) (list (cdr entry)) [] void void))
               selected))
         (harness (TestHarness "Scheme DSL closure" (TestConfig verbosity: 5 capture-output?: #f) modules))
         (result (test-run! harness)))
    (force-output)
    (if (test-result-ok? result)
      (begin (displayln "OK") (force-output) (exit 0))
      (exit 1))))
