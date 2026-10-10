;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite test-case check-equal? check-exception)
        :gerbil-ascent/candidate/annotations
        (only-in :gerbil-ascent/candidate/program candidate-inspect)
        (only-in :gerbil-ascent/candidate/reasoning reasoning-source-snapshot
                 reasoning-attempt reasoning-receipt-status reasoning-receipt-rows
                 reasoning-receipt-candidate-digest))
(export ascent-annotations-test)
(def (count-attempt source candidate (work 100000) (cap 1000000) (edges 4096))
  (let (receipt (reasoning-attempt source candidate #f))
    (candidate-positive-counts source (candidate-inspect source candidate)
      (reasoning-receipt-candidate-digest receipt) (reasoning-receipt-status receipt)
      (reasoning-receipt-rows receipt) 10000 work cap edges)))
(def arithmetic-candidate
  '(candidate (relation out 1)
     (rule (out ?x) (s ?x) (t ?x))
     (rule (out ?x) (s ?x) (s ?x))
     (query out ?x) (limits 16 64 128)))
(def ascent-annotations-test
  (test-suite "Unit natural semiring derivation annotations"
    (test-case "16 source multiplicities preserve addition and repeated body products"
      (for-each (lambda (m)
        (for-each (lambda (n)
          (let* ((source (reasoning-source-snapshot 'multiplicity 0
                           (list (list 's 1 (make-list m '(7)))
                                 (list 't 1 (make-list n '(7))))))
                 (answer (count-attempt source arithmetic-candidate))
                 (expected (+ (* m n) (* m m))))
            (check-equal? (positive-counts-status answer) 'complete)
            (check-equal? (positive-counts-rows answer)
                          (if (zero? expected) [] (list (list '(7) expected)))))) (iota 4))) (iota 4)))
    (test-case "different rule occurrences remain different alternatives"
      (let* ((source (reasoning-source-snapshot 'rules 0 '((s 1 ((7) (7))))))
             (p '(candidate (relation out 1)
                   (rule (out ?x) (s ?x)) (rule (out ?x) (s ?x))
                   (query out ?x) (limits 8 16 32)))
             (answer (count-attempt source p)))
        (check-equal? (positive-counts-status answer) 'complete)
        (check-equal? (positive-counts-rows answer) '(((7) 4)))))
    (test-case "productive recursion cannot publish a finite count"
      (let* ((source (reasoning-source-snapshot 'cycle 0 '((s 1 ((7))))))
             (p '(candidate (relation out 1)
                   (rule (out ?x) (s ?x)) (rule (out ?x) (out ?x))
                   (query out ?x) (limits 8 16 32)))
             (answer (count-attempt source p 1000 3)))
        (check-equal? (positive-counts-status answer) 'bounded)
        (check-equal? (positive-counts-reason answer) 'count-limit)
        (check-equal? (positive-counts-rows answer) []))
      ;; Syntactic recursion without a seed creates no proof trees.
      (let* ((source (reasoning-source-snapshot 'unseeded 0 '((s 1 ()))))
             (p '(candidate (relation out 1) (rule (out ?x) (out ?x))
                   (query out ?x) (limits 8 16 32)))
             (answer (count-attempt source p)))
        (check-equal? (positive-counts-status answer) 'complete)
        (check-equal? (positive-counts-rows answer) [])))
    (test-case "work, numeric and graph refusal keep all rows private"
      (let* ((source (reasoning-source-snapshot 'limits 0 '((s 1 ((7) (7))) (t 1 ((7))))))
             (full (count-attempt source arithmetic-candidate))
             (work (positive-counts-work full)))
        (check-equal? (positive-counts-status (count-attempt source arithmetic-candidate work)) 'complete)
        (for-each (lambda (answer)
          (check-equal? (positive-counts-status answer) 'bounded)
          (check-equal? (positive-counts-rows answer) []))
          (list (count-attempt source arithmetic-candidate (- work 1))
                (count-attempt source arithmetic-candidate 100000 5)
                (count-attempt source arithmetic-candidate 100000 1000000 1)))
        (check-exception (count-attempt source arithmetic-candidate 0) true)
        (check-exception (count-attempt source arithmetic-candidate 100000 0) true)
        (check-equal? (positive-counts-rows full) '(((7) 6)))))
    (test-case "published rows detach from mutable source rows"
      (let* ((source (reasoning-source-snapshot 'ownership 0 '((s 1 ((7))) (t 1 ((7))))))
             (answer (count-attempt source arithmetic-candidate))
             (again (count-attempt source arithmetic-candidate)))
        (set-car! (caar (positive-counts-rows answer)) 99)
        (check-equal? (positive-counts-rows again) '(((7) 2)))
        (check-equal? (positive-counts-rows (count-attempt source arithmetic-candidate))
                      '(((7) 2)))))))
