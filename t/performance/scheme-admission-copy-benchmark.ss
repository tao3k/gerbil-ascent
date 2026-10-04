;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Isolate the copy and validation removed at three checked boundaries.
;;; The old and new variants run in one process with alternating order.
;;; Full admission, replacement and fixed-point solve costs are excluded.
(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/scheme-checked
                 relational-copy-row relational-copy-rows relational-source))

(def (old-admission rows)
  (relational-source 'edge 2 (relational-copy-rows rows 2)))

(def (new-admission rows)
  (relational-source 'edge 2 rows))

(def (old-update rows)
  (let (copied (relational-copy-rows rows 2))
    (relational-source 'edge 2 copied)
    copied))

(def (new-update rows)
  (relational-copy-rows rows 2))

(def (old-append rows)
  (let (copied (car (relational-copy-rows (list (car rows)) 2)))
    (relational-source 'edge 2 (list copied))
    copied))

(def (new-append rows)
  (relational-copy-row (car rows) 2))

(def (sample kind variant procedure rows repetitions result-kind)
  (let ((started (current-jiffy)) (last #f))
    (let loop ((i 0))
      (when (< i repetitions)
        (set! last (procedure rows))
        (loop (+ i 1))))
    (let* ((micros (quotient (* (- (current-jiffy) started) 1000000)
                             (jiffies-per-second)))
           (actual
            (case result-kind
              ((relation) (.ref last 'rows))
              ((row) (list last))
              (else last))))
      (unless (and (equal? actual rows)
                   (not (eq? (car actual) (car rows))))
        (error "row-copy benchmark changed rows or retained a caller row"
               variant))
      (displayln kind " " variant " " micros)
      (force-output))))

(def (case-run label rows repetitions old new result-kind)
  (displayln "CASE " label " " (length rows) " " repetitions)
  (force-output)
  (sample "WARM" 'old old rows repetitions result-kind)
  (sample "WARM" 'new new rows repetitions result-kind)
  (for-each
   (lambda (pair)
     (if (even? pair)
       (begin
         (sample "SAMPLE" 'old old rows repetitions result-kind)
         (sample "SAMPLE" 'new new rows repetitions result-kind))
       (begin
         (sample "SAMPLE" 'new new rows repetitions result-kind)
         (sample "SAMPLE" 'old old rows repetitions result-kind))))
   (iota 8)))

(def bulk-rows
  (map (lambda (i) (list i (modulo i 17))) (iota 512)))

(case-run 'admission bulk-rows 20
          old-admission new-admission 'relation)
(case-run 'replacement bulk-rows 20
          old-update new-update 'rows)
(case-run 'append '((1 2)) 1000
          old-append new-append 'row)
(displayln "OK")
(force-output)
(exit 0)
