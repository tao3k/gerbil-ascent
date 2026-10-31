;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        :gerbil-ascent/t/performance/strata-preflight/fixture)
(export ascent-strata-preflight-test)
(def ascent-strata-preflight-test
  (test-suite "Strict dependency preflight before edge construction"
    (test-case "multihead mixed clauses and all storage kinds match frozen diagnostics"
      (for-each
       (lambda (mask)
         (let (kinds (list->vector (map (lambda (n) (if (bit-set? n mask) 'lattice 'relation)) (iota 3))))
           (for-each
            (lambda (left)
              (for-each
               (lambda (right)
                 (for-each
                  (lambda (cycle?)
                    (let (plans
                          (append (list (vector (list (vector 1 []) (vector 2 []) (vector 1 []))
                                                (list (vector left (vector 0 []))
                                                      (vector 'guard #f)
                                                      (vector right (vector 0 []))) 2 0))
                                  (if cycle? (list (vector (list (vector 0 []))
                                                          (list (vector 'atom (vector 1 []))) 1 1)) [])))
                      (check-equal? (strata-preflight-outcome #f plans kinds)
                                    (strata-preflight-outcome #t plans kinds)))) '(#f #t)))
               '(atom negation aggregate))) '(atom negation aggregate)))) (iota 8)))
    (test-case "nonreading clauses and positive lattice-only rules need zero strata"
      (let* ((plans (strata-preflight-plans 16 4 'atom)) (before (car plans))
             (heads (vector-ref before 0)) (body (vector-ref before 1))
             (kinds (make-vector 17 'lattice)))
        (vector-set! before 1 (cons (vector 'generator #f) (cons (vector 'guard #f) body)))
        (check-equal? (strata-preflight-outcome #f plans kinds) (make-vector 17 0))
        (check-equal? (eq? heads (vector-ref before 0)) #t)
        (check-equal? (cddr (vector-ref before 1)) body)
        (check-equal? (strata-preflight-outcome #f [] '#()) '#())))
    (test-case "competing strict cycle errors retain reverse dependency priority"
      (for-each
       (lambda (order)
         (let* ((plans (list (vector (list (vector 0 []))
                                    (map (lambda (kind) (vector kind (vector 0 []))) order) 0 0)))
                (expected (if (eq? (last order) 'aggregate)
                            "unstratifiable ASCENT aggregate cycle"
                            "unstratifiable ASCENT negation cycle")))
           (check-equal? (strata-preflight-outcome #f plans '#(relation)) expected)
           (check-equal? (strata-preflight-outcome #f plans '#(relation))
                         (strata-preflight-outcome #t plans '#(relation)))))
       '((negation aggregate) (aggregate negation))))
    (test-case "cold and warm public solves retain independent expected rows"
      (for-each
       (lambda (old?)
         (let (program (strata-preflight-program 4 2))
           (check-equal? (strata-preflight-solve old? program #t) (make-list 5 '((7))))
           (check-equal? (strata-preflight-solve old? program #f) (make-list 5 '((7))))
           (check-equal? (strata-preflight-solve old? program #f) (make-list 5 '((7)))))) '(#t #f)))))
