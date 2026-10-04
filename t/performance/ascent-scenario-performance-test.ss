;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite)
        (only-in :gerbil-ascent/t/performance/native-library assert-native-library!)
        (only-in :core/observability/testing-case poo-flow-test-case/with)
        (only-in :gerbil-ascent/t/performance/ascent-ss-profile
                 ascent-ss-profile))

(export ascent-scenario-performance-test)

(def ascent-scenario-performance-test
  (test-suite "ASCENT SS scenario"
    (poo-flow-test-case/with ascent-ss-profile "bounded scenario"
      (let (path (getenv "ASCENT_SS_SCENARIO"))
        (unless (and path (file-exists? path))
          (error "ASCENT_SS_SCENARIO must name a scenario file" path))
        (assert-native-library!)
        (load path)))))
