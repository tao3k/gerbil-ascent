;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/program/aggregators
        (prefix-in :gerbil-ascent/t/performance/aggregate-input/reference old-))
(export ascent-aggregate-input-test)
(def (numeric-observation value)
  (cond ((and (real? value) (inexact? value) (not (= value value))) 'nan)
        ((and (real? value) (inexact? value) (zero? value)) (list 'zero (/ 1.0 value)))
        (else value)))
(def (aggregate-observation call tuples)
  (map numeric-observation (call tuples)))
(def (compare-aggregates values)
  (let (tuples (map list values))
    (for-each
     (lambda (old new)
       (check-equal? (aggregate-observation new tuples) (aggregate-observation old tuples)))
     (list old-gerbil-ascent-sum old-gerbil-ascent-mean old-gerbil-ascent-min old-gerbil-ascent-max)
     (list gerbil-ascent-sum gerbil-ascent-mean gerbil-ascent-min gerbil-ascent-max))))
(def ascent-aggregate-input-test
  (test-suite "Aggregate input admission and reduction"
    (test-case "finite ordered numeric inputs match all original builtins"
      (def alphabet '(-2 0 3 1/2 2.0))
      (def (inputs width)
        (if (zero? width) (list [])
          (foldl (lambda (value prior)
                   (append prior (map (cut cons value <>) (inputs (- width 1))))) [] alphabet)))
      (for-each (lambda (width) (for-each compare-aggregates (inputs width))) (iota 5)))
    (test-case "signed zeros infinities NaNs and large exact values retain numeric behavior"
      (for-each compare-aggregates
                (list (list -0.0 0.0) (list 0.0 -0.0) (list +inf.0 1 -inf.0)
                      (list +nan.0 1 2) (list 1 +nan.0 2)
                      (list 9007199254740993 9007199254740992.0 9007199254740992)
                      (list 1e16 1.0 -1e16 2.0))))
    (test-case "sum and mean retain complex arithmetic and fold operand order"
      (let (tuples '((1+2i) (3) (-2+1i)))
        (check-equal? (gerbil-ascent-sum tuples) (old-gerbil-ascent-sum tuples))
        (check-equal? (gerbil-ascent-mean tuples) (old-gerbil-ascent-mean tuples))))
    (test-case "complete shape admission takes priority over earlier numeric failure"
      (for-each
       (lambda (call)
         (check-equal?
          (with-catch (lambda (e) (error-message e)) (cut call '((not-a-number) (1 2))))
          "ASCENT aggregator expects one input column")
         (check-exception (call '((not-a-number))) true))
       (list gerbil-ascent-sum gerbil-ascent-mean gerbil-ascent-min gerbil-ascent-max)))
    (test-case "structural shape admission rejects improper and cyclic individual tuples"
      (let (cycle (list 1))
        (set-cdr! cycle cycle)
        (for-each
         (lambda (call)
           (for-each (lambda (tuple)
                       (check-equal? (with-catch (lambda (e) (error-message e)) (cut call (list tuple)))
                                     "ASCENT aggregator expects one input column"))
                     (list [] '(1 2) '(1 . 2) cycle)))
         (list gerbil-ascent-sum gerbil-ascent-mean gerbil-ascent-min gerbil-ascent-max))))
    (test-case "caller tuple and outer list spines remain unchanged"
      (let* ((tuples '((1) (2) (3))) (first (car tuples)) (rest (cdr tuples)))
        (for-each (lambda (call) (call tuples))
                  (list gerbil-ascent-sum gerbil-ascent-mean gerbil-ascent-min gerbil-ascent-max))
        (check-equal? tuples '((1) (2) (3)))
        (check-equal? (eq? first (car tuples)) #t)
        (check-equal? (eq? rest (cdr tuples)) #t)))))
