;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/test/base
 :gerbil-ascent/t/qualification/ascent-selected-activation-test
 :gerbil-ascent/t/qualification/ascent-positive-components-test

 :gerbil-ascent/t/qualification/ascent-affected-outputs-test)
(export main)
(def (main)
 (let* ((suites (list ascent-selected-activation-test ascent-positive-components-test ascent-affected-outputs-test))
        (modules (map (lambda (s) (TestModule (TestObject-info s) (list s) [] void void)) suites))
        (result (test-run! (TestHarness "Affected outputs" (TestConfig verbosity: 5 capture-output?: #f) modules))))
  (unless (test-result-ok? result) (exit 42)) (displayln "OK") (force-output) (exit 0)))
