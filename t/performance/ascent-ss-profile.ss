;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        (only-in :core/observability/debug poo-flow-debug-memory-policy)
        (only-in :core/observability/testing-case
                 poo-flow-default-testing-case-profile))

(export ascent-ss-profile)

(def ascent-ss-profile
  (.o (:: @ poo-flow-default-testing-case-profile)
      (identity 'ascent/ss)
      (memory-policy
       (poo-flow-debug-memory-policy
        'ascent/ss
        heap-limit-bytes: 805306368
        live-growth-limit-bytes: 268435456
        sample-interval-milliseconds: 25))
      (max-duration-milliseconds 175000)))
