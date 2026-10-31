;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/program/aggregators
        (prefix-in :gerbil-ascent/t/performance/aggregate-input/reference old-))
(export aggregate-input aggregate-workflow aggregate-expected)
(def (aggregate-input width count shape)
  (let* ((tuples (map (lambda (n) (list (- (modulo n 97) 48))) (iota count)))
         (remainder (modulo count 97))
         ;; A complete 97-value cycle sums to zero. Sum the remaining progression.
         (sum (- (quotient (* remainder (- remainder 1)) 2) (* 48 remainder)))
         (expected
          (case shape
            ((count) (list count))
            ((extrema) (if (zero? count) (list [] [])
                         (list (list -48) (list (if (>= count 97) 48 (- count 49))))))
            (else (list (list sum) (if (zero? count) [] (list (/ (exact->inexact sum) count))))))))
    (vector (make-list width (if (eq? shape 'count) (make-list count []) tuples))
            shape (make-list width expected))))
(def (aggregate-workflow old? input)
  (map (lambda (tuples)
    (case (vector-ref input 1)
      ((count) ((if old? old-gerbil-ascent-count gerbil-ascent-count) tuples))
      ((extrema) (list ((if old? old-gerbil-ascent-min gerbil-ascent-min) tuples)
                      ((if old? old-gerbil-ascent-max gerbil-ascent-max) tuples)))
      (else (list ((if old? old-gerbil-ascent-sum gerbil-ascent-sum) tuples)
                  ((if old? old-gerbil-ascent-mean gerbil-ascent-mean) tuples)))))
       (vector-ref input 0)))
(def (aggregate-expected input) (vector-ref input 2))
