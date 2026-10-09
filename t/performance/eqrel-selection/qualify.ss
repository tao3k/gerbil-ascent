;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/test/base
 :gerbil-ascent/t/qualification/ascent-eqrel-views-test
 :gerbil-ascent/t/qualification/ascent-provider-views-test
 :gerbil-ascent/t/qualification/ascent-relation-view-test)
(export main)
(def (main)
 (let* ((suites (list ascent-eqrel-views-test ascent-provider-views-test ascent-relation-view-test))
        (modules (map (lambda (suite) (TestModule (TestObject-info suite) (list suite) [] void void)) suites))
        (result (test-run! (TestHarness "Eqrel injection selection" (TestConfig verbosity: 5 capture-output?: #f) modules))))
  (unless (test-result-ok? result) (exit 42))
  (displayln "OK") (force-output) (exit 0)))
