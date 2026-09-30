;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-case test-suite)
        (only-in :gerbil-ascent/program/operator
                 relational-op-source relational-op-union
                 relational-op-join relational-op-select-eq
                 relational-op-project relational-op-flatmap
                 relational-op-fix relational-op-compile)
        (only-in :gerbil-ascent/program/scheme-language
                 relational-admit relational-solve relational-query-name)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt
                 reasoning-receipt-status reasoning-receipt-rows))

(export scheme-operator-test)

(def (reachability edge)
  (relational-op-fix
   2
   (lambda (path)
     (relational-op-union
      edge
      (relational-op-project
       (relational-op-join path edge 1 0) '(0 3))))))

(def (solve-op operator (input-limit 32) (derived-limit 256))
  (let-values (((program output)
                (relational-op-compile operator input-limit
                                       derived-limit 512)))
    (relational-query-name
     (relational-solve (relational-admit program)) output)))

(def (same-rows? actual expected)
  (and (= (length actual) (length expected))
       (andmap (lambda (row) (if (member row expected) #t #f)) actual)))

;;; Independent transitive closure over three finite vertices.
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

(def scheme-operator-test
  (test-suite "Scheme finite relation operator graph"
    (test-case "sixty-four graph fixed points equal independent closure"
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
                  (actual
                   (solve-op
                    (reachability
                     (relational-op-source 'edge 2 edges))))
                  (candidate
                   (reasoning-attempt
                    (reasoning-source-snapshot
                     'graph mask (list (list 'edge 2 edges)))
                    '(candidate
                       (relation path 2)
                       (rule (path ?x ?y) (edge ?x ?y))
                       (rule (path ?x ?z)
                             (path ?x ?y) (edge ?y ?z))
                       (query path ?from ?to)
                       (limits 16 32 64)))))
             (check-equal? (reasoning-receipt-status candidate) 'complete)
             (check-equal? (same-rows? actual
                                       (reference-closure edges)) #t)
             (check-equal?
              (same-rows? actual (reasoning-receipt-rows candidate)) #t)))
         (iota 64))))
    (test-case "select, project, finite flatmap and union share one solve"
      (let* ((pairs
              (relational-op-source 'pair 2
                                    '((1 a) (2 b) (2 c) (3 a))))
             (selected (relational-op-select-eq pairs 0 2))
             (letters (relational-op-project selected '(1)))
             (mapped
              (relational-op-flatmap
               letters 1 '(((b) (10)) ((b) (11)) ((c) (12)))))
             (extra (relational-op-source 'extra 1 '((13))))
             (actual (solve-op (relational-op-union mapped extra))))
        (check-equal? (same-rows? actual '((10) (11) (12) (13))) #t)))
    (test-case "fixed-point placeholder is local to its builder"
      (let* ((seed (relational-op-source 'seed 1 '((1))))
             (identity-fix
              (relational-op-fix 1 (lambda (current) current)))
             (with-seed
              (relational-op-fix
               1 (lambda (current)
                   (relational-op-union seed current)))))
        (check-equal? (solve-op identity-fix) '())
        (check-equal? (solve-op with-seed) '((1)))))
    (test-case "shared child cannot capture a fixed-point parameter"
      (let* ((source (relational-op-source 'source 1 '((1))))
             (child #f)
             (fixed
              (relational-op-fix
               1 (lambda (parameter)
                   (set! child (relational-op-union source parameter))
                   child))))
        (check-exception
         (solve-op (relational-op-union fixed child)) true)))
    (test-case "one source withdrawal recompiles to a new complete result"
      (let* ((input (list (list 0 1) (list 1 2)))
             (operator
              (reachability (relational-op-source 'edge 2 input))))
        (set-car! (car input) 99)
        (let* ((first (solve-op operator))
               (second
                (solve-op
                 (reachability
                  (relational-op-source 'edge 2 '((0 1)))))))
          (check-equal? (same-rows? first '((0 1) (1 2) (0 2))) #t)
          (check-equal? second '((0 1))))))
    (test-case "two builder instances retain separate private names"
      (let* ((left (reachability
                    (relational-op-source 'left-edge 2 '((1 2) (2 3)))))
             (right (reachability
                     (relational-op-source 'right-edge 2 '((4 5)))))
             (combined (relational-op-union left right)))
        (let-values (((first-program first-output)
                      (relational-op-compile combined 16 256 512))
                     ((second-program second-output)
                      (relational-op-compile combined 16 256 512)))
          (check-equal? (eq? first-output second-output) #f)
          (check-equal?
           (same-rows?
            (relational-query-name
             (relational-solve (relational-admit first-program))
             first-output)
            '((1 2) (2 3) (1 3) (4 5))) #t)
          (check-equal?
           (same-rows?
            (relational-query-name
             (relational-solve (relational-admit second-program))
             second-output)
            '((1 2) (2 3) (1 3) (4 5))) #t))))
    (test-case "construction rejects hidden code and invalid shapes"
      (let ((edge (relational-op-source 'edge 2 '((1 2)))))
        (check-exception (relational-op-union edge
                       (relational-op-source 'one 1 '((1)))) true)
        (check-exception (relational-op-join edge edge 2 0) true)
        (check-exception (relational-op-project edge '(0 2)) true)
        (check-exception
         (relational-op-flatmap edge 1 '(((1 2) (1 2)))) true)
        (check-exception (relational-op-select-eq edge 0
                                                 (lambda (x) x)) true)
        (check-exception
         (solve-op (relational-op-union
                    edge (relational-op-source 'edge 2 '((2 3)))))
         true)))
    (test-case "growth budget cannot return a complete fixed point"
      (let (edge (relational-op-source 'edge 2
                                        '((0 1) (1 2) (2 3))))
        (check-exception (solve-op (reachability edge) 8 1) true)))))
