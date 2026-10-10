;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :gerbil-ascent/t/native/artifact-admission artifact-directory!)
        (only-in :gerbil-ascent/t/performance/native-library assert-native-library!)
        (only-in :gerbil-ascent/t/performance/change-plan-runner qualify-change-plan))
(export ascent-change-plan-performance-test)
(def ascent-change-plan-performance-test
  (test-suite "Owned change plan lifecycle"
    (test-case "64 requests include admission and preserve semantic controls"
      (assert-native-library!)
      (artifact-directory! ".cache/ascent/change-plan")
      (for-each (lambda (shape)
                  (check-equal? (qualify-change-plan shape
                    (string-append ".cache/ascent/change-plan/" shape ".ss")) #t))
                '("single" "empty" "small" "identity" "unique" "fanout" "miss" "fix")))))
