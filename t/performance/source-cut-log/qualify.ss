;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/test/base
 :gerbil-ascent/t/qualification/ascent-actor-session-test
 :gerbil-ascent/t/qualification/ascent-source-log-test
 :gerbil-ascent/t/performance/ascent-source-cut-allocation-test)
(export main)
(def (main)
 (let* ((suites (list ascent-actor-session-test ascent-source-log-test ascent-source-cut-allocation-test))
        (modules (map (lambda (suite) (TestModule (TestObject-info suite) (list suite) [] void void)) suites))
        (result (test-run! (TestHarness "Persistent source cuts" (TestConfig verbosity: 5 capture-output?: #f) modules))))
  (unless (test-result-ok? result) (exit 42))
  (displayln "OK") (force-output) (exit 0)))
