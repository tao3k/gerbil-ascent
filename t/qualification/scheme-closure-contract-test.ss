;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-case test-suite)
        (only-in :gerbil-ascent/program/scheme-language
                 relational-program relational-fragment relational-export
                 relational-compose relational-admit relational-admit/report
                 relational-admission-report-diagnostic relational-diagnostic-code
                 relational-solve relational-query-name))
(export scheme-closure-contract-test)

(def (successor-program bounded?)
  (if bounded?
    (relational-program
     (relation number (value) '((0)))
     (rule (number ?next) (number ?n)
       (where (< ?n 4)) (compute ?next (+ ?n 1)))
     (limits 8 8 16))
    (relational-program
     (relation number (value) '((0)))
     (rule (number ?next) (number ?n) (compute ?next (+ ?n 1)))
     (limits 8 8 16))))

(def scheme-closure-contract-test
  (test-suite "Scheme closure guarantees and operational failure boundaries"
    (test-case "finite successor completes with the exact independent interval"
      (let (answer (relational-query-name
                    (relational-solve (relational-admit (successor-program #t)))
                    'number))
        (check-equal? (length answer) 5)
        (for-each (lambda (n) (check-equal? (if (member (list n) answer) #t #f) #t))
                  '(0 1 2 3 4))))
    (test-case "monotone integer successor does not become complete at a budget"
      (let (admission (relational-admit (successor-program #f)))
        (check-exception (relational-solve admission)
          (lambda (failure)
            (equal? (error-message failure) "ASCENT derived fact budget exceeded")))
        ;; Failed admissions cannot subsequently publish a truncated closure.
        (check-exception (relational-solve admission)
          (lambda (failure)
            (equal? (error-message failure) "relational solve previously failed")))))
    (test-case "one lattice key does not imply finite-height refinement"
      (let (admission
            (relational-admit
             (relational-program
              (lattice best (key value) '((0 0)) max)
              (rule (best ?key ?next) (best ?key ?n)
                (compute ?next (+ ?n 1)))
              (limits 8 8 16))))
        (check-exception (relational-solve admission)
          (lambda (failure)
            (equal? (error-message failure) "ASCENT derived fact budget exceeded")))
        (check-exception (relational-solve admission)
          (lambda (failure)
            (equal? (error-message failure) "relational solve previously failed")))))
    (test-case "separately admissible fragments can compose into a negative cycle"
      (let* ((base
              (relational-fragment
               (import) (source (seed (value) '((1)))
                                (a (value) []) (b (value) []))
               (private) (export (seed seed) (a a) (b b))))
             (seed (relational-export base 'seed))
             (a (relational-export base 'a))
             (b (relational-export base 'b))
             (left
              (relational-fragment
               (import (seed seed) (a a) (b b)) (source) (private) (export)
               (rule (a ?x) (seed ?x) (not (b ?x)))))
             (right
              (relational-fragment
               (import (seed seed) (a a) (b b)) (source) (private) (export)
               (rule (b ?x) (seed ?x) (not (a ?x)))))
             (combined (relational-compose (list base left right) 8 8 16)))
        (relational-solve (relational-admit (relational-compose (list base left) 8 8 16)))
        (relational-solve (relational-admit (relational-compose (list base right) 8 8 16)))
        (check-equal?
         (relational-diagnostic-code
          (relational-admission-report-diagnostic (relational-admit/report combined)))
         'invalid-dependencies)
        (check-exception (relational-admit combined) true)))))
