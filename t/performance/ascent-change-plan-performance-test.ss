;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :gerbil-ascent/t/harness/artifact-admission artifact-directory!)
        (only-in :gerbil-ascent/t/performance/library assert-native-library!)
        (only-in :gerbil-ascent/t/performance/change-plan-runner qualify-change-plan))
(export ascent-change-plan-performance-test)
(def (check-shape shape)
  (assert-native-library!)
  (artifact-directory! ".cache/ascent/change-plan")
  (check-equal? (qualify-change-plan shape
    (string-append ".cache/ascent/change-plan/" shape ".ss")) #t))
(def ascent-change-plan-performance-test
  (test-suite "Owned change plan lifecycle"
    (test-case "single retains 64 requests and admission" (check-shape "single"))
    (test-case "empty retains 64 requests and admission" (check-shape "empty"))
    (test-case "small retains 64 requests and admission" (check-shape "small"))
    (test-case "identity retains 64 requests and admission" (check-shape "identity"))
    (test-case "unique retains 64 requests and admission" (check-shape "unique"))
    (test-case "fanout retains 64 requests and admission" (check-shape "fanout"))
    (test-case "miss retains 64 requests and admission" (check-shape "miss"))
    (test-case "fix retains 64 requests and admission" (check-shape "fix"))
  ))
