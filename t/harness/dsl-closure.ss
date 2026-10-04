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

(import (only-in :gerbil-ascent/t/qualification/scheme-provenance-graph-test
                 scheme-provenance-graph-test))

(import (only-in :gerbil-ascent/t/qualification/scheme-higher-order-test
                 scheme-higher-order-test))

(import (only-in :gerbil-ascent/t/qualification/scheme-session-deletion-test
                 scheme-session-deletion-test))

(import (only-in :gerbil-ascent/t/qualification/scheme-stratified-provenance-test
                 scheme-stratified-provenance-test))

(def (main . args)
  (let* ((entries
          (list
                (cons "t/qualification/scheme-closure-contract-test.ss" scheme-closure-contract-test)
                (cons "t/qualification/scheme-provenance-graph-test.ss" scheme-provenance-graph-test)
                (cons "t/qualification/scheme-higher-order-test.ss" scheme-higher-order-test)
                (cons "t/qualification/scheme-session-deletion-test.ss" scheme-session-deletion-test)
                (cons "t/qualification/scheme-stratified-provenance-test.ss" scheme-stratified-provenance-test)
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
