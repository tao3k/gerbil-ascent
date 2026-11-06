;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/test/base
 :gerbil-ascent/t/qualification/ascent-scc-summary-test
 :gerbil-ascent/t/qualification/scheme-session-deletion-test
 :gerbil-ascent/t/qualification/ascent-positive-components-test)
(export main)
(def (main)
 (let* ((suites (list ascent-scc-summary-test scheme-session-deletion-test ascent-positive-components-test))
        (modules (map (lambda (suite) (TestModule (TestObject-info suite) (list suite) [] void void)) suites))
        (result (test-run! (TestHarness "Dependency graph consumers" (TestConfig verbosity: 5 capture-output?: #f) modules))))
  (unless (test-result-ok? result) (exit 42))
  (displayln "OK") (force-output) (exit 0)))
