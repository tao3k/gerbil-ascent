;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Aggregate procedures consume matched tuples and return zero or more values,
;;; following Ascent's iterator-producing aggregator contract.
(import (only-in :clan/poo/support/base lambda-match))
(export gerbil-ascent-count gerbil-ascent-sum gerbil-ascent-min
        gerbil-ascent-max gerbil-ascent-mean)

;;; One structural admission contract for retained extrema and streamed folds.
;;; Complete shape validation precedes arithmetic, including a later bad tuple.
;; : (forall (a) (-> [a] a))
;; : (-> SingletonTuple Value)
(def single-column-value
  (lambda-match
    ([value] value)
    (tuple (error "ASCENT aggregator expects one input column" tuple))))

;;; Bind borrowed tuples once. Validation retains no column spine and invokes
;;; no numeric operation; the consumer chooses its own ordered reduction state.
;; : (-> Tuples InputBinding BodyExpressions AggregateResult)
(defrule (with-single-column tuples input body ...)
  (let (input tuples)
    (for-each single-column-value input)
    body ...))

;; : (-> [EmptyTuple] [Natural])
(def (gerbil-ascent-count tuples)
  (for-each
   (lambda (tuple)
     (unless (null? tuple)
       (error "ASCENT count expects no input columns" tuple)))
   tuples)
  (list (length tuples)))

;; : (-> [NumericTuple] [Number])
(def (gerbil-ascent-sum tuples)
  (with-single-column tuples input
    (list (foldl (lambda (tuple sum) (+ (car tuple) sum)) 0 input))))

;; : (-> [RealTuple] [Real])
(def (gerbil-ascent-min tuples)
  (let (values (map single-column-value tuples))
    (if (null? values) [] (list (apply min values)))))

;; : (-> [RealTuple] [Real])
(def (gerbil-ascent-max tuples)
  (let (values (map single-column-value tuples))
    (if (null? values) [] (list (apply max values)))))

;; : (-> [NumericTuple] [InexactNumber])
(def (gerbil-ascent-mean tuples)
  (with-single-column tuples input
    (if (null? input)
      []
      (let (count 0)
        (let (sum (foldl (lambda (tuple prior)
                          (set! count (+ count 1))
                          (+ (car tuple) prior)) 0 input))
          (list (/ (exact->inexact sum) count)))))))
