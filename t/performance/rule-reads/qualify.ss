;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/test/base
 :gerbil-ascent/t/qualification/ascent-strata-test
 :gerbil-ascent/t/qualification/ascent-strata-preflight-test

 :gerbil-ascent/t/qualification/ascent-rule-reads-test)
(export main)
(def (main)
 (let* ((suites (list ascent-strata-test ascent-strata-preflight-test ascent-rule-reads-test))
        (modules (map (lambda (s) (TestModule (TestObject-info s) (list s) [] void void)) suites))
        (result (test-run! (TestHarness "Rule reads" (TestConfig verbosity: 5 capture-output?: #f) modules))))
  (unless (test-result-ok? result) (exit 42)) (displayln "OK") (force-output) (exit 0)))
