;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; A counterexample to promoting the SDK net-stack statistic to allocation events.
(declare (standard-bindings) (extended-bindings) (block))
(define samples (make-f64vector 2))
(define gc-at-depth 0.)
(define (deep n)
  (if (= n 0)
    (begin
      (##get-bytes-allocated! samples 0)
      (set! gc-at-depth (f64vector-ref (##process-statistics) 6))
      0)
    (let ((rest (deep (- n 1)))) (+ rest n))))
(define result (deep 20000))
(##get-bytes-allocated! samples 1)
(write (list (f64vector-ref samples 0) (f64vector-ref samples 1)
             (- (f64vector-ref (##process-statistics) 6) gc-at-depth) result))
(newline)
