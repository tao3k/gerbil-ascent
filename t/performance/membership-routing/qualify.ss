;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/test/base
 :gerbil-ascent/t/qualification/ascent-relation-view-test
 :gerbil-ascent/t/qualification/ascent-provider-views-test
 :gerbil-ascent/t/qualification/ascent-trrel-uf-test
 :gerbil-ascent/t/qualification/ascent-uf-commit-test
 :gerbil-ascent/t/qualification/ascent-membership-routing-test)
(export main)
(def (main)
 (let* ((suites (list ascent-relation-view-test ascent-provider-views-test ascent-trrel-uf-test ascent-uf-commit-test ascent-membership-routing-test))
        (modules (map (lambda (suite) (TestModule (TestObject-info suite) (list suite) [] void void)) suites))
        (result (test-run! (TestHarness "Membership routing" (TestConfig verbosity: 5 capture-output?: #f) modules))))
  (unless (test-result-ok? result) (exit 42))
  (displayln "OK") (force-output) (exit 0)))
