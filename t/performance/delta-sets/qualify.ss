;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/test/base
 :gerbil-ascent/t/qualification/scheme-operator-test
 :gerbil-ascent/t/qualification/scheme-operator-retained-test
 :gerbil-ascent/t/qualification/scheme-higher-order-test
 :gerbil-ascent/t/qualification/ascent-delta-sets-test)
(export main)
(def (main)
 (let* ((suites (list scheme-operator-test scheme-operator-retained-test scheme-higher-order-test ascent-delta-sets-test))
        (modules (map (lambda (s) (TestModule (TestObject-info s) (list s) [] void void)) suites))
        (result (test-run! (TestHarness "Delta sets" (TestConfig verbosity: 5 capture-output?: #f) modules))))
  (unless (test-result-ok? result) (exit 42)) (displayln "OK") (exit 0)))
