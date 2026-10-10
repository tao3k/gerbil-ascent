;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Static entry for existing consumer Suites; std/test owns execution/verdicts.
(import :std/test :std/test/base
        :gerbil-ascent/t/qualification/ascent-positive-plan-test
        :gerbil-ascent/t/qualification/ascent-expression-plan-test
        :gerbil-ascent/t/qualification/ascent-index-entry-test
        :gerbil-ascent/t/qualification/ascent-positive-components-test
        :gerbil-ascent/t/qualification/ascent-actor-session-test
        :gerbil-ascent/t/qualification/scheme-native-integration-test)
(export main)
(def (main)
  (let* ((suites (list ascent-positive-plan-test ascent-expression-plan-test
                      ascent-index-entry-test ascent-positive-components-test
                      ascent-actor-session-test scheme-native-integration-test))
         (modules (map (lambda (suite) (TestModule (TestObject-info suite) (list suite) [] void void)) suites))
         (harness (TestHarness "Atom projection consumers" (TestConfig verbosity: 5 capture-output?: #f) modules))
         (result (test-run! harness)))
    (unless (test-result-ok? result) (exit 42))
    (displayln "OK") (force-output) (exit 0)))
