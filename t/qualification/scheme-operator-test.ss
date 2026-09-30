;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-case test-suite)
        (only-in :gerbil-ascent/program/operator
                 relational-op-source relational-op-union
                 relational-op-join relational-op-select-eq
                 relational-op-project relational-op-flatmap
                 relational-op-fix relational-op-compile
                 relational-op-function relational-op-apply
                 relational-op-fragment relational-op-reference
                 relational-op-reference-change
                 relational-op-measure
                 relational-op-measurement-join-probes
                 relational-op-measurement-fix-body-evaluations)
        (only-in :gerbil-ascent/program/interface
                 relational-admit relational-solve relational-query-name
                 relational-compose relational-export
                 relational-open-session relational-session-run
                 relational-session-append-source!
                 relational-session-replace-source! relational-query
                 relational-op-delta-change)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt
                 reasoning-receipt-status reasoning-receipt-rows))

(export scheme-operator-test)

(def (reachability edge)
  (let (step
        (relational-op-function
         2
         (lambda (path)
           (relational-op-project
            (relational-op-join path edge 1 0) '(0 3)))))
    (relational-op-fix
     2
     (lambda (path)
       (relational-op-union edge
                            (relational-op-apply step path))))))

;;; An inner fixed point depends on the outer parameter. This is a bounded
;;; operational check; it does not assert a higher-order change theorem.
(def (nested-reachability edge)
  (relational-op-fix
   2 (lambda (outer)
       (relational-op-fix
        2 (lambda (inner)
            (relational-op-union
             edge
             (relational-op-union
              outer
              (relational-op-project
               (relational-op-join inner edge 1 0) '(0 3)))))))))

(def (solve-op operator (input-limit 32) (derived-limit 256))
  (let-values (((program output)
                (relational-op-compile operator input-limit
                                       derived-limit 512)))
    (relational-query-name
     (relational-solve (relational-admit program)) output)))

(def (same-rows? actual expected)
  (and (= (length actual) (length expected))
       (andmap (lambda (row) (if (member row expected) #t #f)) actual)))

(def (mask-edges mask possible)
  (let loop ((remaining possible) (bit 1) (rows []))
    (if (null? remaining)
      (reverse rows)
      (loop (cdr remaining) (* bit 2)
            (if (zero? (bitwise-and mask bit)) rows
              (cons (car remaining) rows))))))

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
           (let* ((edges (mask-edges mask possible))
                  (graph
                   (reachability
                    (relational-op-source 'edge 2 edges)))
                  (actual (solve-op graph))
                  (reference (relational-op-reference graph))
                  (fragment (relational-op-fragment graph 'reach))
                  (fragment-rows
                   (relational-query
                    (relational-solve
                     (relational-admit
                      (relational-compose (list fragment) 32 256 512)))
                    fragment 'reach))
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
             (check-equal? (same-rows? actual reference) #t)
             (check-equal? (same-rows? fragment-rows reference) #t)
             (check-equal?
              (same-rows? actual (reasoning-receipt-rows candidate)) #t)))
         (iota 64))))
    (test-case "reference change matches finite closure set difference"
      (let ((possible '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))
            (closure
             (relational-op-function
              2 (lambda (edge) (reachability edge)))))
        (for-each
         (lambda (mask)
           (let* ((before (mask-edges mask possible))
                  (after (cons '(0 1) before))
                  (expected-base (reference-closure before))
                  (expected-grown (reference-closure after))
                  (expected-delta
                   (filter (lambda (row)
                             (not (member row expected-base)))
                           expected-grown)))
             (let-values (((base grown delta)
                           (relational-op-reference-change
                            closure before '((0 1)))))
               (check-equal? (same-rows? base expected-base) #t)
               (check-equal? (same-rows? grown expected-grown) #t)
               (check-equal? (same-rows? delta expected-delta) #t))
             (let-values (((base grown delta)
                           (relational-op-delta-change
                            closure before '((0 1)))))
               (check-equal? (same-rows? base expected-base) #t)
               (check-equal? (same-rows? grown expected-grown) #t)
               (check-equal? (same-rows? delta expected-delta) #t))))
         (iota 64))))
    (test-case "both changing join sides and a finite map propagate inserts"
      (let* ((transformer
              (relational-op-function
               2 (lambda (input)
                   (relational-op-flatmap
                    (relational-op-project
                     (relational-op-join input input 0 0) '(1 3))
                    1 '(((a a) (same))
                        ((a b) (mixed))
                        ((b a) (mixed))
                        ((b b) (same)))))))
             (before '((k a)))
             (added '((k b))))
        (let-values (((base grown delta)
                      (relational-op-delta-change
                       transformer before added)))
          (check-equal? base '((same)))
          (check-equal? (same-rows? grown '((same) (mixed))) #t)
          (check-equal? delta '((mixed)))
          (let-values (((reference-base reference-grown
                         reference-delta)
                        (relational-op-reference-change
                         transformer before added)))
            (check-equal? (same-rows? base reference-base) #t)
            (check-equal? (same-rows? grown reference-grown) #t)
            (check-equal? (same-rows? delta reference-delta) #t)))))
    (test-case "selection after join sees only new paths"
      (let (transformer
            (relational-op-function
             2 (lambda (edge)
                 (relational-op-select-eq
                  (relational-op-project
                   (relational-op-join edge edge 1 0) '(0 3))
                  0 'a))))
        (let-values (((base grown delta)
                      (relational-op-delta-change
                       transformer '((a b)) '((b c)))))
          (check-equal? base '())
          (check-equal? grown '((a c)))
          (check-equal? delta '((a c))))))
    (test-case "nested fixed points with an outer changing parameter"
      (let ((possible '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))
            (transformer
             (relational-op-function
              2 (lambda (edge) (nested-reachability edge)))))
        (for-each
         (lambda (mask)
           (let* ((before (mask-edges mask possible))
                  (after (cons '(0 1) before))
                  (expected-base (reference-closure before))
                  (expected-grown (reference-closure after)))
             (let-values (((base grown delta)
                           (relational-op-delta-change
                            transformer before '((0 1)))))
               (check-equal? (same-rows? base expected-base) #t)
               (check-equal? (same-rows? grown expected-grown) #t)
               (check-equal?
                (same-rows? delta
                            (filter
                             (lambda (row)
                               (not (member row expected-base)))
                             expected-grown)) #t))))
         '(0 1 3 7 17 31 42 63))))
    (test-case "zero-change propagation avoids old recursive joins"
      (let* ((closure
              (relational-op-function
               2 (lambda (edge) (reachability edge))))
             (before '((0 1) (1 2) (2 3) (3 4) (4 5)))
             (added '((5 6)))
             (reference
              (relational-op-measure
               (lambda ()
                 (relational-op-reference-change
                  closure before added))))
             (delta
              (relational-op-measure
               (lambda ()
                 (relational-op-delta-change
                  closure before added)))))
        (check-equal?
         (< (relational-op-measurement-join-probes delta)
            (relational-op-measurement-join-probes reference)) #t)
        (check-equal?
         (< (relational-op-measurement-fix-body-evaluations delta)
            (relational-op-measurement-fix-body-evaluations reference))
         #t)))
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
             (graph (relational-op-union mapped extra))
             (actual (solve-op graph)))
        (check-equal? (same-rows? actual '((10) (11) (12) (13))) #t)
        (check-equal? (same-rows? actual
                                  (relational-op-reference graph)) #t)))
    (test-case "fixed-point placeholder is local to its builder"
      (let* ((seed (relational-op-source 'seed 1 '((1))))
             (identity-fix
              (relational-op-fix 1 (lambda (current) current)))
             (with-seed
              (relational-op-fix
               1 (lambda (current)
                   (relational-op-union seed current)))))
        (check-equal? (solve-op identity-fix) '())
        (check-equal? (solve-op with-seed) '((1)))
        (check-equal? (relational-op-reference identity-fix) '())
        (check-equal? (relational-op-reference with-seed) '((1)))))
    (test-case "one relation transformer applies to two distinct inputs"
      (let* ((mapping '(((1) (10)) ((2) (20))))
             (transformer
              (relational-op-function
               1 (lambda (input)
                   (relational-op-flatmap input 1 mapping))))
             (left (relational-op-source 'left 1 '((1))))
             (right (relational-op-source 'right 1 '((2))))
             (graph
              (relational-op-union
               (relational-op-apply transformer left)
               (relational-op-apply transformer right))))
        (check-equal? (same-rows? (solve-op graph) '((10) (20))) #t)
        (check-equal?
         (same-rows? (relational-op-reference graph) '((10) (20))) #t)
        (let-values (((base grown delta)
                      (relational-op-reference-change
                       transformer '((1)) '((2)))))
          (check-equal? base '((10)))
          (check-equal? (same-rows? grown '((10) (20))) #t)
          (check-equal? delta '((20))))
        (let-values (((base grown delta)
                      (relational-op-delta-change
                       transformer '((1)) '((2)))))
          (check-equal? base '((10)))
          (check-equal? (same-rows? grown '((10) (20))) #t)
          (check-equal? delta '((20))))))
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
    (test-case "operator graphs compose as fresh native fragments"
      (let* ((left
              (relational-op-fragment
               (reachability
                (relational-op-source 'edge 2 '((1 2) (2 3))))
               'reach))
             (right
              (relational-op-fragment
               (reachability
                (relational-op-source 'edge 2 '((4 5))))
               'reach))
             (session
              (relational-open-session
               (relational-compose (list left right) 16 32 64)))
             (first (relational-session-run session)))
        (check-equal? (eq? (relational-export left 'edge)
                          (relational-export right 'edge)) #f)
        (check-equal? (same-rows? (relational-query first left 'reach)
                                  '((1 2) (2 3) (1 3))) #t)
        (check-equal? (relational-query first right 'reach) '((4 5)))
        (relational-session-replace-source!
         session left 'edge '((7 8)))
        (let (second (relational-session-run session))
          (check-equal? (relational-query second left 'reach) '((7 8)))
          (check-equal? (relational-query second right 'reach) '((4 5)))
          (check-equal? (same-rows? (relational-query first left 'reach)
                                    '((1 2) (2 3) (1 3))) #t))))
    (test-case "delta prediction matches retained append and withdrawal"
      (let* ((before '((1 2) (2 3)))
             (added '((3 4)))
             (closure
              (relational-op-function
               2 (lambda (edge) (reachability edge))))
             (fragment
              (relational-op-fragment
               (relational-op-apply
                closure (relational-op-source 'edge 2 before))
               'path))
             (session
              (relational-open-session
               (relational-compose (list fragment) 16 64 128)))
             (first (relational-session-run session)))
        (let-values (((base grown delta)
                      (relational-op-delta-change
                       closure before added)))
          (check-equal?
           (same-rows? (relational-query first fragment 'path) base) #t)
          (check-exception
           (relational-session-append-source!
            session fragment 'edge '(bad)) true)
          (relational-session-append-source!
           session fragment 'edge (car added))
          (let (second (relational-session-run session))
            (check-equal?
             (same-rows? (relational-query second fragment 'path)
                         grown) #t)
            (check-equal?
             (same-rows? delta '((1 4) (2 4) (3 4))) #t)
            (check-equal?
             (same-rows? (relational-query first fragment 'path)
                         base) #t)
            (relational-session-replace-source!
             session fragment 'edge before)
            (let (third (relational-session-run session))
              (check-equal?
               (same-rows? (relational-query third fragment 'path)
                           base) #t)
              (check-equal?
               (same-rows? (relational-query second fragment 'path)
                           grown) #t))))))
    (test-case "construction rejects hidden code and invalid shapes"
      (let ((edge (relational-op-source 'edge 2 '((1 2)))))
        (check-exception (relational-op-union edge
                       (relational-op-source 'one 1 '((1)))) true)
        (check-exception (relational-op-join edge edge 2 0) true)
        (check-exception
         (relational-op-apply
          (relational-op-function 1 (lambda (input) input)) edge)
         true)
        (check-exception
         (relational-op-delta-change
          (relational-op-function 2 (lambda (input) input))
          '((1 2)) '((2 3)) 1)
         true)
        (check-exception (relational-op-project edge '(0 2)) true)
        (check-exception
         (relational-op-flatmap edge 1 '(((1 2) (1 2)))) true)
        (check-exception (relational-op-select-eq edge 0
                                                 (lambda (x) x)) true)
        (check-exception
         (solve-op (relational-op-union
                    edge (relational-op-source 'edge 2 '((2 3)))))
         true)
        (check-exception (relational-op-fragment edge 'edge) true)))
    (test-case "growth budget cannot return a complete fixed point"
      (let (edge (relational-op-source 'edge 2
                                        '((0 1) (1 2) (2 3))))
        (check-exception (solve-op (reachability edge) 8 1) true)
        (check-exception
         (relational-op-reference (reachability edge) 1) true)))))
