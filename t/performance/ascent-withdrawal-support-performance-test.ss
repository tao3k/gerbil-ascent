;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :gerbil-ascent/t/native/artifact-admission artifact-directory!)
        (only-in :gerbil-ascent/t/performance/native-library assert-native-library!)
        (only-in :gerbil-ascent/t/performance/withdrawal-support/runner qualify-withdrawal-support))
(export ascent-withdrawal-support-performance-test)
(def ascent-withdrawal-support-performance-test
  (test-suite "Stable support complete deletion lifecycle"
    (test-case "construction every source cut and independent outputs remain matched"
      (assert-native-library!)
      (artifact-directory! ".cache/ascent/withdrawal-support")
      (for-each (lambda (shape)
                  (check-equal? (qualify-withdrawal-support shape
                    (string-append ".cache/ascent/withdrawal-support/" shape ".ss")) #t))
                '("chain" "diamond" "duplicates" "tiny")))))
