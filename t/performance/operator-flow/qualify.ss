;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/test/base
 :gerbil-ascent/t/qualification/scheme-operator-retained-test
 :gerbil-ascent/t/qualification/scheme-operator-test
 :gerbil-ascent/t/qualification/scheme-higher-order-test
 :gerbil-ascent/t/qualification/scheme-native-integration-test)
(export main)
(def (main)
 (let* ((suites (list scheme-operator-retained-test scheme-operator-test scheme-higher-order-test scheme-native-integration-test))
        (modules (map (lambda (suite) (TestModule (TestObject-info suite) (list suite) [] void void)) suites))
        (result (test-run! (TestHarness "Operator compiler flow" (TestConfig verbosity: 5 capture-output?: #f) modules))))
  (unless (test-result-ok? result) (exit 42))
  (displayln "OK") (force-output) (exit 0)))
