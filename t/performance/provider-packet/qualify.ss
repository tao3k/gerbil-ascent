;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/test/base
        :gerbil-ascent/t/qualification/ascent-byods-index-test
        :gerbil-ascent/t/qualification/ascent-provider-packet-test
        :gerbil-ascent/t/qualification/ascent-index-lifecycle-test)
(export main)
(def (main)
  (let* ((suites (list ascent-byods-index-test ascent-provider-packet-test ascent-index-lifecycle-test))
         (modules (map (lambda (s) (TestModule (TestObject-info s) (list s) [] void void)) suites))
         (result (test-run! (TestHarness "Provider packet"
                            (TestConfig verbosity: 5 capture-output?: #f) modules))))
    (unless (test-result-ok? result) (exit 42))
    (displayln "OK") (force-output) (exit 0)))
