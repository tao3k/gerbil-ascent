;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :gerbil-ascent/core/positive-plan gerbil-ascent-compile-positive-plan
                 gerbil-ascent-run-positive-plan! make-positive-plan-cost
                 call-with-positive-plan-cost positive-plan-cost-snapshot)
        (only-in :gerbil-ascent/program/index gerbil-ascent-make-row-indexes
                 row-indexes-rows row-indexes-old-rows)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider))
(export delta-join-test)

(def (join-chain count fresh)
  (let* ((edges (map (lambda (id) (list id (+ id 1))) (iota count)))
         (delta (take edges fresh))
         (x '(variable . x))
         (y '(variable . y))
         (z '(variable . z))
         (first (vector 0 (list x y) [] (list x y) []))
         (second (vector 0 (list y z) '(0) (list y z) (list y)))
         (head (vector 0 (list x z)))
         (plan (gerbil-ascent-compile-positive-plan
                 (list head) (list (vector 'atom first) (vector 'atom second)))))
    (lambda (disjoint?)
      (let* ((index (gerbil-ascent-make-row-indexes
                     (vector edges) (vector delta) (vector count) (vector fresh)
                     (vector 0) (vector 0) (vector gerbil-ascent-hash-index-provider)))
             (probe (row-indexes-rows index))
             (old-probe (and disjoint? (row-indexes-old-rows index)))
             (frame (make-vector 3 #f))
             (rows []))
        (for-each
         (lambda (pivot)
           (gerbil-ascent-run-positive-plan! plan frame pivot probe
             (lambda (_ row) (set! rows (cons row rows))) #f #f old-probe))
         '(0 1))
        rows))))

(def (read-work receipt name) (cdr (assq name receipt)))

(def (measure-join count fresh)
  (let* ((run (join-chain count fresh))
         ;; A witness x -> x+1 -> x+2 is fresh exactly when x < fresh.
         (ids (iota (min fresh (- count 1))))
         (duplicated (append ids (iota (- fresh 1)))))
    (def (observe disjoint? expected)
      (let* ((before (cpu-time))
             (result (run disjoint?))
             (cpu-us (* 1000000. (- (cpu-time) before)))
             (cost (make-positive-plan-cost #f #f))
             (counted (call-with-positive-plan-cost cost (cut run disjoint?)))
             (work (positive-plan-cost-snapshot cost)))
        (check-equal? (list-sort < (map car result)) (list-sort < expected))
        (check-equal? (list-sort < (map car counted)) (list-sort < expected))
        (check-equal? (andmap (lambda (row) (= (cadr row) (+ 2 (car row)))) result) #t)
        (check-equal? (read-work work 'complete-witnesses) (length expected))
        (display "DELTA-JOIN ")
        (write (list (cons 'input-rows count) (cons 'delta-rows fresh)
                     (cons 'disjoint? disjoint?) (cons 'cpu-us cpu-us)
                     (cons 'candidate-rows (read-work work 'candidate-rows))
                     (cons 'complete-witnesses (read-work work 'complete-witnesses))
                     (cons 'index-probes (read-work work 'physical-index-probes))
                     (cons 'old-membership-rows (read-work work 'old-membership-input-rows))))
        (newline)
        work))
    (let* ((ordinary (observe #f duplicated))
           (disjoint (observe #t ids)))
      (check (< (read-work disjoint 'complete-witnesses)
                (read-work ordinary 'complete-witnesses)) => #t))))

(def delta-join-test
  (test-suite "Indexed two-pivot delta joins"
    (test-case "fixed sparse medium and full deltas agree with an independent chain oracle"
      (for-each (cut measure-join 16384 <>) '(128 4096 16384)))))
