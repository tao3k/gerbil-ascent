;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Matched local E4 probe. This measures the finite set interpreters,
;;; including their row storage; it does not benchmark the native rule plan.
(import (only-in :gerbil-ascent/program/operator
                 relational-op-function relational-op-fix
                 relational-op-union relational-op-project
                 relational-op-join relational-op-apply
                 relational-op-reference-change
                 relational-op-measure
                 relational-op-measurement-result-values
                 relational-op-measurement-join-probes
                 relational-op-measurement-fix-body-evaluations)
        (only-in :gerbil-ascent/program/operator-change
                 relational-op-delta-change))

(def (reachability edge)
  (let (step
        (relational-op-function
         2 (lambda (path)
             (relational-op-project
              (relational-op-join path edge 1 0) '(0 3)))))
    (relational-op-fix
     2 (lambda (path)
         (relational-op-union edge
                              (relational-op-apply step path))))))

(def closure
  (relational-op-function 2 (lambda (edge) (reachability edge))))

(def (chain n)
  (map (lambda (i) (list i (+ i 1))) (iota (- n 1))))

(def (star n)
  (map (lambda (i) (list 0 i)) (iota (- n 1) 1)))

;;; Independent Floyd-Warshall set model; never timed with either method.
(def (finite-closure edges vertex-count)
  (let (matrix (make-vector (* vertex-count vertex-count) #f))
    (for-each
     (lambda (edge)
       (vector-set! matrix
                    (+ (* vertex-count (car edge)) (cadr edge)) #t))
     edges)
    (for-each
     (lambda (pivot)
       (for-each
        (lambda (from)
          (for-each
           (lambda (to)
             (when (and (vector-ref matrix
                                    (+ (* vertex-count from) pivot))
                        (vector-ref matrix
                                    (+ (* vertex-count pivot) to)))
               (vector-set! matrix
                            (+ (* vertex-count from) to) #t)))
           (iota vertex-count)))
        (iota vertex-count)))
     (iota vertex-count))
    (let (rows [])
      (for-each
       (lambda (from)
         (for-each
          (lambda (to)
            (when (vector-ref matrix (+ (* vertex-count from) to))
              (set! rows (cons (list from to) rows))))
          (iota vertex-count)))
       (iota vertex-count))
      rows)))

(def (same-rows? actual expected)
  (and (= (length actual) (length expected))
       (andmap (lambda (row) (member row expected)) actual)))

(def (sample method procedure before added expected-base
             expected-grown expected-delta)
  (let* ((started (current-jiffy))
         (measurement
          (relational-op-measure
           (lambda () (procedure closure before added))))
         (elapsed
          (quotient (* (- (current-jiffy) started) 1000000)
                    (jiffies-per-second)))
         (results (relational-op-measurement-result-values measurement)))
    (unless (and (same-rows? (car results) expected-base)
                 (same-rows? (cadr results) expected-grown)
                 (same-rows? (caddr results) expected-delta))
      (error "change probe disagrees with independent closure" method))
    (displayln "SAMPLE " method " " elapsed " "
               (relational-op-measurement-join-probes measurement) " "
               (relational-op-measurement-fix-body-evaluations measurement))))

(def (case-run shape n make-before)
  (let* ((before (make-before n))
         (added (list (list (- n 1) n)))
         (base (finite-closure before (+ n 1)))
         (grown (finite-closure (append before added) (+ n 1)))
         (delta (filter (lambda (row) (not (member row base))) grown)))
    (displayln "CASE " shape " " n " " (length base) " "
               (length grown) " " (length delta))
    ;; Warm both paths, then alternate their order for five paired samples.
    (relational-op-reference-change closure before added)
    (relational-op-delta-change closure before added)
    (for-each
     (lambda (index)
       (displayln "PAIR " index)
       (if (even? index)
         (begin
           (sample 'reference relational-op-reference-change
                   before added base grown delta)
           (sample 'delta relational-op-delta-change
                   before added base grown delta))
         (begin
           (sample 'delta relational-op-delta-change
                   before added base grown delta)
           (sample 'reference relational-op-reference-change
                   before added base grown delta))))
     (iota 5))))

(for-each (lambda (n) (case-run 'chain n chain)) '(12 24 36))
(for-each (lambda (n) (case-run 'star n star)) '(12 24 36))
