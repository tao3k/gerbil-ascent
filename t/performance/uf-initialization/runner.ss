;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/t/performance/paired-study :gerbil-ascent/t/performance/uf-initialization/fixture)
(export main)
(def (main scenario receipt-path)
  (let* ((contract (call-with-input-file "t/performance/uf-initialization/benchmark.ss" read))
         (batch-size (cdr (assq 'allocationQueryBatchSize contract))))
    (run-paired-study contract ui-prepare ui-consume ui-expected scenario receipt-path
      (cut ui-allocate <> <> <> <> batch-size))))
