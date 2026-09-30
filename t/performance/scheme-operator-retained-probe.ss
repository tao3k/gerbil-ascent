;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Matched native Session update probe. Fresh build+solve and retained
;;; append+run answer the same grown graph; neither timing includes the
;;; independent model or construction of the old retained Session.
(import (only-in :gerbil-ascent/program/interface
                 relational-op-function relational-op-fix
                 relational-op-union relational-op-project
                 relational-op-join relational-op-apply
                 relational-op-open-retained relational-op-retained-rows
                 relational-op-retained-append!))

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
       (andmap (lambda (row) (if (member row expected) #t #f)) actual)))

(def (elapsed-us thunk)
  (let (start (current-jiffy))
    (let (result (thunk))
      (values
       (quotient (* (- (current-jiffy) start) 1000000)
                 (jiffies-per-second))
       result))))

(def (sample method before added expected)
  (let-values (((micros actual)
                (if (eq? method 'retained)
                  (let (session
                        (relational-op-open-retained
                         closure before 64 8192 16384))
                    (elapsed-us
                     (lambda ()
                       (relational-op-retained-append!
                        session (car added))
                       (relational-op-retained-rows session))))
                  (elapsed-us
                   (lambda ()
                     (relational-op-retained-rows
                      (relational-op-open-retained
                       closure (append before added)
                       64 8192 16384)))))))
    (unless (same-rows? actual expected)
      (error "native retained probe disagrees with independent closure"
             method))
    (displayln "SAMPLE " method " " micros)))

(def (case-run shape n make-before)
  (let* ((before (make-before n))
         (added (list (list (- n 1) n)))
         (expected (finite-closure (append before added) (+ n 1))))
    (displayln "CASE " shape " " n " " (length expected))
    ;; Warm both paths; then alternate order to expose obvious drift.
    (sample 'retained before added expected)
    (sample 'fresh before added expected)
    (for-each
     (lambda (index)
       (displayln "PAIR " index)
       (if (even? index)
         (begin
           (sample 'retained before added expected)
           (sample 'fresh before added expected))
         (begin
           (sample 'fresh before added expected)
           (sample 'retained before added expected))))
     (iota 5))))

;;; Full lifecycle comparison: one initial materialization plus eleven
;;; successive insertions versus a fresh materialization at each revision.
;;; This includes retained startup, unlike the single-update cases above.
(def (sequence-sample method initial additions expected)
  (let-values (((micros answers)
                (elapsed-us
                 (lambda ()
                   (if (eq? method 'retained)
                     (let (session
                           (relational-op-open-retained
                            closure initial 64 8192 16384))
                       (let loop ((rest additions)
                                  (rows (list
                                         (relational-op-retained-rows
                                          session))))
                         (if (null? rest)
                           (reverse rows)
                           (begin
                             (relational-op-retained-append!
                              session (car rest))
                             (loop (cdr rest)
                                   (cons (relational-op-retained-rows
                                          session) rows))))))
                     (let loop ((current initial) (rest additions)
                                (rows []))
                       (let (answer
                             (relational-op-retained-rows
                              (relational-op-open-retained
                               closure current 64 8192 16384)))
                         (if (null? rest)
                           (reverse (cons answer rows))
                           (loop (append current (list (car rest)))
                                 (cdr rest)
                                 (cons answer rows))))))))))
    (unless (and (= (length answers) (length expected))
                 (andmap same-rows? answers expected))
      (error "native retained lifecycle disagrees with independent closure"
             method))
    (displayln "LIFECYCLE SAMPLE " method " " micros)))

(def (sequence-run)
  (let* ((initial (chain 13))
         (additions (list-tail (chain 24) 12))
         (expected
          (let loop ((current initial) (rest additions)
                     (rows (list (finite-closure initial 24))))
            (if (null? rest)
              (reverse rows)
              (let (next (append current (list (car rest))))
                (loop next (cdr rest)
                      (cons (finite-closure next 24) rows)))))))
    (displayln "SEQUENCE chain 24 " (length additions))
    (sequence-sample 'retained initial additions expected)
    (sequence-sample 'fresh initial additions expected)
    (for-each
     (lambda (index)
       (displayln "SEQUENCE-PAIR " index)
       (if (even? index)
         (begin
           (sequence-sample 'retained initial additions expected)
           (sequence-sample 'fresh initial additions expected))
         (begin
           (sequence-sample 'fresh initial additions expected)
           (sequence-sample 'retained initial additions expected))))
     (iota 3))))

(for-each (lambda (n) (case-run 'chain n chain)) '(12 24 36))
(for-each (lambda (n) (case-run 'star n star)) '(12 24 36))
(sequence-run)
