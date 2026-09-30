;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite test-case)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt
                 reasoning-snapshot-digest
                 reasoning-receipt-status reasoning-receipt-rows
                 reasoning-receipt-diagnostics reasoning-receipt-evidence
                 reasoning-receipt-snapshot-generation
                 reasoning-receipt-snapshot-digest
                 reasoning-diagnostic-code reasoning-diagnostic-path
                 reasoning-evidence-kind reasoning-evidence-support
                 reasoning-evidence-reachable))

(export ascent-reasoning-library-test)

(def (proposal origin target (extra []) (limits '(limits 16 32 64)))
  (append
   '(candidate
      (relation path 2)
      (rule (path ?x ?y) (edge ?x ?y))
      (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z)))
   extra
   (list (list 'query 'path origin target) limits)))

(def (first-diagnostic receipt)
  (car (reasoning-receipt-diagnostics receipt)))

(def (edge-snapshot generation rows)
  (reasoning-source-snapshot 'graph generation
                             (list (list 'edge 2 rows))))

;;; Reference closure enumerates vertex triples, without using rule engine.
(def (reference-closure edges)
  (let (matrix (make-vector 9 #f))
    (for-each
     (lambda (edge)
       (vector-set! matrix (+ (* 3 (car edge)) (cadr edge)) #t))
     edges)
    (for-each
     (lambda (pivot)
       (for-each
        (lambda (from)
          (for-each
           (lambda (to)
             (when (and (vector-ref matrix (+ (* 3 from) pivot))
                        (vector-ref matrix (+ (* 3 pivot) to)))
               (vector-set! matrix (+ (* 3 from) to) #t)))
           '(0 1 2)))
        '(0 1 2)))
     '(0 1 2))
    (let (rows [])
      (for-each
       (lambda (from)
         (for-each
          (lambda (to)
            (when (vector-ref matrix (+ (* 3 from) to))
              (set! rows (cons (list from to) rows))))
          '(0 1 2)))
       '(0 1 2))
      (reverse rows))))

(def (same-rows? actual expected)
  (and (= (length actual) (length expected))
       (andmap (lambda (row) (if (member row expected) #t #f)) actual)))

(def ascent-reasoning-library-test
  (test-suite "bounded inert reasoning library"
    (test-case "complete witness, absent cut, withdrawal, and retained receipt"
      (let* ((input (list (list 1 2) (list 2 3)))
             (first (edge-snapshot 1 input))
             (present (reasoning-attempt first (proposal 1 3)))
             (absent (reasoning-attempt first (proposal 1 4))))
        (check-equal? (reasoning-receipt-status present) 'complete)
        (check-equal? (reasoning-receipt-rows present) '((1 3)))
        (check-equal? (reasoning-evidence-kind
                       (reasoning-receipt-evidence present)) 'witness)
        (check-equal? (reasoning-evidence-support
                       (reasoning-receipt-evidence present))
                      '((source 1 (1 2)) (source 2 (2 3))))
        (check-equal? (reasoning-receipt-status absent) 'complete)
        (check-equal? (reasoning-receipt-rows absent) '())
        (check-equal? (reasoning-evidence-kind
                       (reasoning-receipt-evidence absent)) 'cut)
        (check-equal? (reasoning-evidence-reachable
                       (reasoning-receipt-evidence absent)) '(1 2 3))
        (set-car! (car input) 99)
        (check-equal? (reasoning-snapshot-digest first)
                      (reasoning-receipt-snapshot-digest present))
        (let* ((second (edge-snapshot 2 '((1 2))))
               (withdrawn (reasoning-attempt second (proposal 1 3))))
          (check-equal? (reasoning-receipt-snapshot-generation withdrawn) 2)
          (check-equal? (reasoning-receipt-rows withdrawn) '())
          (check-equal? (reasoning-evidence-kind
                         (reasoning-receipt-evidence withdrawn)) 'cut)
          (check-equal? (reasoning-receipt-rows present) '((1 3))))))
    (test-case "hypothetical source fact stays labelled and unpromoted"
      (let* ((snapshot (edge-snapshot 1 '((1 2) (2 3))))
             (candidate (proposal 1 4 '((fact edge 3 4))))
             (hypothesis
              (reasoning-attempt snapshot candidate))
             (without (reasoning-attempt snapshot (proposal 1 4))))
        (set-car! (cddr (list-ref candidate 4)) 99)
        (check-equal? (reasoning-receipt-rows hypothesis) '((1 4)))
        (check-equal? (reasoning-evidence-support
                       (reasoning-receipt-evidence hypothesis))
                      '((source 1 (1 2)) (source 2 (2 3))
                        (candidate 4 (3 4))))
        (check-equal? (reasoning-receipt-rows without) '())))
    (test-case "structural errors have paths"
      (let* ((snapshot (edge-snapshot 1 '((1 2))))
             (bad-helper
              (reasoning-attempt
               snapshot
               '(candidate (relation path 2)
                           (rule (path ?x ?y) (helper ?x ?y))
                           (query path 1 2) (limits 8 8 16))))
             (unsafe
              (reasoning-attempt
               snapshot
               '(candidate (relation path 2)
                           (rule (path ?x ?y) (edge ?x ?z))
                           (query path 1 2) (limits 8 8 16))))
             (variable-fact
              (reasoning-attempt
               snapshot
               '(candidate (fact edge ?x 3)
                           (relation path 2)
                           (rule (path ?x ?y) (edge ?x ?y))
                           (query path 1 2) (limits 8 8 16)))))
        (check-equal? (reasoning-receipt-status bad-helper) 'rejected)
        (check-equal? (reasoning-diagnostic-code
                       (first-diagnostic bad-helper)) 'unknown-relation)
        (check-equal? (reasoning-diagnostic-path
                       (first-diagnostic bad-helper)) '(clause 2 body 1))
        (check-equal? (reasoning-receipt-status unsafe) 'rejected)
        (check-equal? (reasoning-diagnostic-code
                       (first-diagnostic unsafe)) 'unbound-head-variable)
        (check-equal? (reasoning-diagnostic-path
                       (first-diagnostic unsafe)) '(clause 2 head term 2))
        (check-equal? (reasoning-diagnostic-code
                       (first-diagnostic variable-fact)) 'invalid-fact)))
    (test-case "compiling wrong join is observed, not repaired"
      (let* ((snapshot (edge-snapshot 1 '((1 2) (2 3))))
             (wrong
              (reasoning-attempt
               snapshot
               '(candidate (relation path 2)
                           (rule (path ?x ?y) (edge ?x ?y))
                           (rule (path ?x ?z)
                                 (path ?x ?y) (edge ?x ?z))
                           (query path 1 3) (limits 8 16 32)))))
        (check-equal? (reasoning-receipt-status wrong) 'complete)
        (check-equal? (reasoning-receipt-rows wrong) '())
        (check-equal? (reasoning-evidence-kind
                       (reasoning-receipt-evidence wrong)) 'unsupported)))
    (test-case "bounded failure and source declaration validation"
      (let* ((snapshot (edge-snapshot 1 '((1 2) (2 3))))
             (bounded (reasoning-attempt snapshot
                                         (proposal 1 3 [] '(limits 8 1 32)))))
        (check-equal? (reasoning-receipt-status bounded) 'unknown)
        (check-exception
         (reasoning-source-snapshot 'graph 1 '((edge 2 ((1 2)))
                                               (edge 2 ((2 3))))) true)))
    (test-case "nonreflexive empty graph has complete unsupported evidence"
      (let* ((snapshot (edge-snapshot 1 '()))
             (receipt (reasoning-attempt snapshot (proposal 1 1))))
        (check-equal? (reasoning-receipt-status receipt) 'complete)
        (check-equal? (reasoning-receipt-rows receipt) '())
        (check-equal? (reasoning-evidence-kind
                       (reasoning-receipt-evidence receipt)) 'unsupported)))
    (test-case "all sixty-four three-node graphs match finite reference"
      (let (possible '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))
        (for-each
         (lambda (mask)
           (let* ((edges
                   (let loop ((remaining possible) (bit 1) (rows []))
                     (if (null? remaining)
                       (reverse rows)
                       (loop (cdr remaining) (* bit 2)
                             (if (zero? (bitwise-and mask bit)) rows
                               (cons (car remaining) rows))))))
                  (receipt
                   (reasoning-attempt
                    (edge-snapshot mask edges)
                    (proposal '?from '?to [] '(limits 8 16 32)))))
             (check-equal? (reasoning-receipt-status receipt) 'complete)
             (check-equal?
              (same-rows? (reasoning-receipt-rows receipt)
                          (reference-closure edges)) #t)))
         (iota 64))))))
