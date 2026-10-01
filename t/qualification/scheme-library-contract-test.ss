;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One finite specification for the common native/candidate subset.
;;; The matrix below does not call an ASCENT evaluator to obtain expectations.
(import (only-in :std/test check-equal? check-exception test-suite test-case)
        (only-in :gerbil-ascent/program/interface
                 relational-program relational-fragment relational-compose
                 relational-admit relational-solve relational-query-name
                 relational-query relational-open-program-session
                 relational-program-session-run relational-program-transaction!
                 relational-program-query)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt
                 reasoning-receipt-status reasoning-receipt-rows
                 reasoning-receipt-bound?))

(export scheme-library-contract-test)

(def vertices '(0 1 2))
(def possible-edges '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))
(def weights '((0 2) (1 4) (2 6)))
(def roots '((0) (1) (2)))

(def (edges-for-mask mask)
  (let loop ((i 0) (rest possible-edges) (rows []))
    (if (null? rest)
      (reverse rows)
      (loop (+ i 1) (cdr rest)
            (if (not (zero? (bitwise-and mask (arithmetic-shift 1 i))))
              (cons (car rest) rows) rows)))))

(def (same-set? actual expected)
  (and (= (length actual) (length expected))
       (andmap (lambda (row) (if (member row expected) #t #f)) actual)
       (andmap (lambda (row) (if (member row actual) #t #f)) expected)))

(def (model-summary edges blocked supplied-weights supplied-roots)
  (let (matrix (make-vector 9 #f))
    (def (index from to) (+ (* 3 from) to))
    (for-each (lambda (edge)
                (vector-set! matrix (index (car edge) (cadr edge)) #t))
              edges)
    (for-each
     (lambda (via)
       (for-each
        (lambda (from)
          (for-each
           (lambda (to)
             (when (and (vector-ref matrix (index from via))
                        (vector-ref matrix (index via to)))
               (vector-set! matrix (index from to) #t)))
           vertices))
        vertices))
     vertices)
    (map
     (lambda (root)
       (let (origin (car root))
         (list origin
               (apply +
                      (map (lambda (weight) (* 2 (cadr weight)))
                           (filter
                            (lambda (weight)
                              (and (even? (cadr weight))
                                   (vector-ref matrix
                                               (index origin (car weight)))
                                   (not (member
                                         (list origin (car weight))
                                         blocked))))
                            supplied-weights))))))
     supplied-roots)))

(def (native-program edges blocked supplied-weights supplied-roots)
  (relational-program
   (relation edge (from to) edges)
   (relation blocked (from to) blocked)
   (relation weight (node value) supplied-weights)
   (relation root (node) supplied-roots)
   (relation path (from to))
   (relation allowed (from to))
   (relation weighted (from value))
   (relation summary (node total))
   (rule (path ?x ?y) (edge ?x ?y))
   (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
   (rule (allowed ?x ?y) (path ?x ?y) (not (blocked ?x ?y)))
   (rule (weighted ?x ?v)
     (allowed ?x ?y) (weight ?y ?w)
     (where (even? ?w)) (compute ?v (+ ?w ?w)))
   (rule (summary ?r ?n)
     (root ?r) (reduce ?n (sum ?v) (weighted ?r ?v)))
   (limits 16 64 128)))

(def (fragment-program edges blocked-rows supplied-weights supplied-roots)
  (relational-fragment
   (import)
   (source (edge (from to) edges)
           (blocked (from to) blocked-rows)
           (weight (node value) supplied-weights)
           (root (node) supplied-roots))
   (private (path (from to)) (allowed (from to))
            (weighted (from value)) (summary (node total)))
   (export (summary summary))
   (rule (path ?x ?y) (edge ?x ?y))
   (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
   (rule (allowed ?x ?y) (path ?x ?y) (not (blocked ?x ?y)))
   (rule (weighted ?x ?v)
     (allowed ?x ?y) (weight ?y ?w)
     (where (even? ?w)) (compute ?v (+ ?w ?w)))
   (rule (summary ?r ?n)
     (root ?r) (reduce ?n (sum ?v) (weighted ?r ?v)))))

(def candidate
  '(candidate
     (relation path 2) (relation allowed 2)
     (relation weighted 2) (relation summary 2)
     (rule (path ?x ?y) (edge ?x ?y))
     (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
     (rule (allowed ?x ?y) (path ?x ?y) (not (blocked ?x ?y)))
     (rule (weighted ?x ?v)
       (allowed ?x ?y) (weight ?y ?w)
       (where (even? ?w)) (compute ?v (+ ?w ?w)))
     (rule (summary ?r ?n)
       (root ?r) (reduce ?n (sum ?v) (weighted ?r ?v)))
     (query summary ?r ?n) (limits 16 64 128)))

(def (candidate-result generation edges blocked supplied-weights supplied-roots)
  (let* ((snapshot
          (reasoning-source-snapshot
           'contract generation
           (list (list 'edge 2 edges) (list 'blocked 2 blocked)
                 (list 'weight 2 supplied-weights)
                 (list 'root 1 supplied-roots))))
         (receipt (reasoning-attempt snapshot candidate)))
    (check-equal? (reasoning-receipt-status receipt) 'complete)
    (check-equal? (reasoning-receipt-bound? receipt snapshot candidate) #t)
    (reasoning-receipt-rows receipt)))

(def (check-all generation edges blocked supplied-weights supplied-roots)
  (let* ((expected (model-summary edges blocked supplied-weights supplied-roots))
         (direct
          (relational-query-name
           (relational-solve
            (relational-admit
             (native-program edges blocked supplied-weights supplied-roots)))
           'summary))
         (fragment
          (fragment-program edges blocked supplied-weights supplied-roots))
         (composed
          (relational-query
           (relational-solve
            (relational-admit
             (relational-compose (list fragment) 16 64 128)))
           fragment 'summary))
         (observed
          (candidate-result generation edges blocked supplied-weights
                            supplied-roots)))
    (check-equal? (same-set? direct expected) #t)
    (check-equal? (same-set? composed expected) #t)
    (check-equal? (same-set? observed expected) #t)))

(def scheme-library-contract-test
  (test-suite "native and candidate common semantic contract"
    (test-case "eight diagnostic graphs share one finite model"
      (for-each
       (lambda (mask)
         (check-all mask (edges-for-mask mask) '((0 2)) weights roots)
         (displayln "CONTRACT-PROGRESS " mask)
         (force-output))
       '(0 1 3 7 24 31 47 63)))
    (test-case "multi-source withdrawal and failed transaction are atomic"
      (let* ((edges '((0 1) (1 2)))
             (session
              (relational-open-program-session
               (native-program edges '((0 2)) weights roots)))
             (first (relational-program-session-run session))
             (expected-first (model-summary edges '((0 2)) weights roots))
             (second
              (relational-program-transaction!
               session (list (cons 'edge '((0 1)))
                             (cons 'blocked '())
                             (cons 'weight '((1 8) (2 6))))))
             (expected-second
              (model-summary '((0 1)) '() '((1 8) (2 6)) roots)))
        (check-equal?
         (same-set? (relational-program-query first 'summary)
                    expected-first) #t)
        (check-equal?
         (same-set? (relational-program-query second 'summary)
                    expected-second) #t)
        (check-equal?
         (same-set? (candidate-result 2 '((0 1)) '()
                                      '((1 8) (2 6)) roots)
                    expected-second) #t)
        (check-exception
         (relational-program-transaction!
          session (list (cons 'edge '((0 1) (9 "bad")))
                        (cons 'root '((0))))) true)
        (check-equal?
         (same-set? (relational-program-query
                     (relational-program-session-run session) 'summary)
                    expected-second) #t)
        (check-equal?
         (same-set? (relational-program-query first 'summary)
                    expected-first) #t)))
    (test-case "resource exhaustion is never a completed answer"
      (let* ((snapshot
              (reasoning-source-snapshot
               'contract 1
               '((edge 2 ((0 1) (1 2)))
                 (blocked 2 ())
                 (weight 2 ((1 4) (2 6)))
                 (root 1 ((0) (1) (2))))))
             (small
              (append (reverse (cdr (reverse candidate)))
                      '((limits 16 1 128))))
             (receipt (reasoning-attempt snapshot small))
             (session
              (relational-open-program-session
               (native-program '((0 1) (1 2)) '()
                               '((1 4) (2 6)) roots)))
             (complete (relational-program-session-run session)))
        (check-equal? (reasoning-receipt-status receipt) 'unknown)
        (check-equal? (reasoning-receipt-rows receipt) '())
        (check-exception
         (relational-program-transaction!
          session
          (list (cons 'edge
                      (map (lambda (i) (list i (+ i 1)))
                           (iota 17))))) true)
        (check-equal?
         (same-set?
          (relational-program-query
           (relational-program-session-run session) 'summary)
          (relational-program-query complete 'summary)) #t)))))
