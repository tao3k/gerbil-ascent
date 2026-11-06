;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/test/base
 :gerbil-ascent/t/qualification/ascent-index-entry-test
 :gerbil-ascent/t/qualification/ascent-index-lifecycle-test
 :gerbil-ascent/t/qualification/ascent-byods-index-test)
(export main)
(def (main)
 (let* ((suites (list ascent-index-entry-test ascent-index-lifecycle-test ascent-byods-index-test))
        (modules (map (lambda (suite) (TestModule (TestObject-info suite) (list suite) [] void void)) suites))
        (result (test-run! (TestHarness "Column order consumers" (TestConfig verbosity: 5 capture-output?: #f) modules))))
  (unless (test-result-ok? result) (exit 42))
  (displayln "OK") (force-output) (exit 0)))
