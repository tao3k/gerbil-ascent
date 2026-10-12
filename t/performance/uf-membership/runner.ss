;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/t/performance/paired-study
        :gerbil-ascent/t/performance/uf-membership/fixture)
(export main)
(def (main scenario receipt-path)
  (run-paired-study (call-with-input-file "t/performance/uf-membership/benchmark.ss" read)
    ui-prepare ui-consume ui-expected scenario receipt-path))
