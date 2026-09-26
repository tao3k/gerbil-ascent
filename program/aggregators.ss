;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Aggregate procedures consume matched tuples and return zero or more values,
;;; following Ascent's iterator-producing aggregator contract.
(export gerbil-ascent-count gerbil-ascent-sum gerbil-ascent-min
        gerbil-ascent-max gerbil-ascent-mean)

(def (single-column tuples)
  (map (lambda (tuple)
         (unless (= (length tuple) 1)
           (error "ASCENT aggregator expects one input column" tuple))
         (car tuple))
       tuples))

(def (gerbil-ascent-count tuples)
  (for-each
   (lambda (tuple)
     (unless (null? tuple)
       (error "ASCENT count expects no input columns" tuple)))
   tuples)
  (list (length tuples)))

(def (gerbil-ascent-sum tuples)
  (list (foldl + 0 (single-column tuples))))

(def (gerbil-ascent-min tuples)
  (let (values (single-column tuples))
    (if (null? values) [] (list (apply min values)))))

(def (gerbil-ascent-max tuples)
  (let (values (single-column tuples))
    (if (null? values) [] (list (apply max values)))))

(def (gerbil-ascent-mean tuples)
  (let (values (single-column tuples))
    (if (null? values)
      []
      (list (/ (exact->inexact (foldl + 0 values))
               (length values))))))
