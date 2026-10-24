;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;;
;;; Compare the current indexed list walk with one row-to-vector pass.
(import (only-in :gerbil-ascent/table/funs gerbil-ascent-index-key))

(def (vector-key row columns)
  (let (source (list->vector row))
    (map (lambda (column) (vector-ref source column)) columns)))

(def (timed projector row columns expected repetitions)
  (let ((start (current-jiffy)) (result #f))
    (let loop ((remaining repetitions))
      (when (> remaining 0)
        (set! result (projector row columns))
        (loop (- remaining 1))))
    (unless (equal? result expected)
      (error "index projection changed column order or values" result expected))
    (quotient (* (- (current-jiffy) start) 1000000000)
              (* repetitions (jiffies-per-second)))))

(def (statistic samples fraction)
  (list-ref (list-sort < samples)
            (- (quotient (* (length samples) fraction) 100) 1)))

(def (run width columns repetitions)
  (let* ((row (iota width))
         (expected (gerbil-ascent-index-key row columns))
         (old []) (new []))
    (displayln "CASE width=" width " columns=" columns
               " repetitions=" repetitions)
    (force-output)
    (for-each
     (lambda (_) (timed gerbil-ascent-index-key row columns expected repetitions)
             (timed vector-key row columns expected repetitions))
     (iota 8))
    (let loop ((sample 0))
      (when (< sample 200)
        (if (even? sample)
          (begin
            (set! old (cons (timed gerbil-ascent-index-key row columns
                                   expected repetitions) old))
            (set! new (cons (timed vector-key row columns expected repetitions)
                            new)))
          (begin
            (set! new (cons (timed vector-key row columns expected repetitions)
                            new))
            (set! old (cons (timed gerbil-ascent-index-key row columns
                                   expected repetitions) old))))
        (when (zero? (modulo (+ sample 1) 50))
          (displayln "PROGRESS " width " " (+ sample 1) "/200")
          (force-output))
        (loop (+ sample 1))))
    (displayln "RESULT width=" width " columns=" (length columns)
               " old-p50=" (statistic old 50)
               " new-p50=" (statistic new 50)
               " old-p95=" (statistic old 95)
               " new-p95=" (statistic new 95)
               " new-wins="
               (foldl (lambda (pair total)
                        (if (< (cdr pair) (car pair)) (+ total 1) total))
                      0 (map cons old new)) "/200")))

(run 4 '(1 0) 500)
(run 8 '(7 1 5 3) 500)
(run 32 '(31 0 29 2 27 4 25 6) 300)
(run 64 '(63 0 61 2 59 4 57 6 55 8 53 10 51 12 49 14) 200)
(run 64 '(63 63 0 0 31 31 15 15) 200)
(displayln "OK")
(force-output)
(exit 0)
