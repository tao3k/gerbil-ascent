;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;; Diagnostic for the pinned SDK; not a cumulative allocation benchmark.
(def retained (make-u8vector 8000000 1))
(##gc)
(def snapshots (make-f64vector 2))
(##get-bytes-allocated! snapshots 0)
(def stats (##exec-stats (lambda () (set! retained #f) (##gc))))
(##get-bytes-allocated! snapshots 1)
(write (list 'allocation-counter-probe
  (inexact->exact (f64vector-ref snapshots 0))
  (inexact->exact (f64vector-ref snapshots 1))
  (cdr (assq 'bytes-allocated stats)) (cdr (assq 'nb-gcs stats))))
(newline)
