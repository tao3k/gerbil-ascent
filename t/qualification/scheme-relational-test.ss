;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :std/list/list append-map delete-duplicates/hash)
        (only-in :clan/poo/object .ref)
        (only-in :clan/poo/mop element?)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :gerbil-ascent/program/types
                 GerbilAscentFragmentContract)
        (only-in :gerbil-ascent/program/objects
                 gerbil-ascent-fragment gerbil-ascent-rule
                 gerbil-ascent-atom gerbil-ascent-guard
                 gerbil-ascent-variable)
        (only-in :gerbil-ascent/program/scheme-language
                 relational-program relational-fragment
                 relational-compose relational-export relational-admit
                 relational-solve relational-query)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program
                 gerbil-ascent-open-session
                 gerbil-ascent-session-replace-source!))

(export scheme-relational-test)

;;; Floyd-Warshall over finite edge pairs, independent of rule evaluation.
(def (reference-closure edges)
  (foldl
   (lambda (pivot paths)
     (delete-duplicates/hash
      (append
       paths
       (append-map
        (lambda (left)
          (if (equal? (cadr left) pivot)
            (filter-map
             (lambda (right)
               (and (equal? (car right) pivot)
                    (list (car left) (cadr right))))
             paths)
            []))
        paths))))
   (delete-duplicates/hash edges)
   (delete-duplicates/hash (append (map car edges) (map cadr edges)))))

(def (same-set? actual expected)
  (and (= (length actual) (length expected))
       (andmap (lambda (row) (if (member row expected) #t #f))
               actual)))

(def (evaluate edges (derived-limit 32))
  (gerbil-ascent-evaluate-program
   (relational-program
    (relation edge (from to) edges)
    (relation path (from to))
    (rule (path ?x ?y) (edge ?x ?y))
    (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
    (limits 32 derived-limit 64))))

(def (evaluate-scalar edges)
  (gerbil-ascent-evaluate-program
   (relational-program
    (relation edge (from to) edges)
    (relation even-edge (from to))
    (relation ordered-sum (value))
    (relation copied-left (value))
    (rule (even-edge ?x ?y)
      (edge ?x ?y)
      (where (even? ?x)))
    (rule (ordered-sum ?z)
      (edge ?x ?y)
      (where (< ?x ?y))
      (compute ?z (+ ?x ?y)))
    (rule (copied-left ?z)
      (edge ?x ?y)
      (compute ?z (identity ?x)))
    (limits 32 32 64))))

(def (rows result name)
  ((.ref result 'rows-of) name))

(def (source-fragment edges)
  (relational-fragment
   (import)
   (source (edge (from to) edges))
   (private)
   (export (edge edge))))

(def (reach-fragment edge-handle)
  (relational-fragment
   (import (edge edge-handle))
   (source)
   (private (path (from to)))
   (export (reach path))
   (rule (path ?x ?y) (edge ?x ?y))
   (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))))

(def (scalar-fragment edge-handle)
  (relational-fragment
   (import (edge edge-handle))
   (source)
   (private (even-edge (from to))
            (ordered-sum (value)))
   (export (even-edge even-edge) (ordered-sum ordered-sum))
   (rule (even-edge ?x ?y)
     (edge ?x ?y)
     (where (even? ?x)))
   (rule (ordered-sum ?z)
     (edge ?x ?y)
     (where (< ?x ?y))
     (compute ?z (+ ?x ?y)))))

(def (unbound-scalar-fragment edge-handle)
  (relational-fragment
   (import (edge edge-handle))
   (source)
   (private (selected (from to)))
   (export (selected selected))
   (rule (selected ?x ?y)
     (edge ?x ?y)
     (where (even? ?missing)))))

(def (selected-fragment)
  (relational-fragment
   (import)
   (source)
   (private (selected (from to)))
   (export (selected selected))))

(def (unbounded-count-fragment)
  (relational-fragment
   (import)
   (source (seed (value) '((1))))
   (private (count (value)))
   (export (count count))
   (rule (count ?x) (seed ?x))
   (rule (count ?next)
     (count ?current)
     (seed ?one)
     (compute ?next (+ ?current ?one)))))

(def scheme-relational-test
  (test-suite "Scheme relational finite positive gate"
    (poo-flow-test-case "two fragment instances retain private identities"
      (let* ((source-a (source-fragment '((1 2) (2 3))))
             (source-b (source-fragment '((7 8))))
             (edge-a (relational-export source-a 'edge))
             (edge-b (relational-export source-b 'edge))
             (reach-a (reach-fragment edge-a))
             (reach-b (reach-fragment edge-b))
             (path-a (relational-export reach-a 'reach))
             (path-b (relational-export reach-b 'reach)))
          (let ((result
                 (relational-solve
                  (relational-admit
                   (relational-compose
                    (list source-a source-b reach-a reach-b)
                    16 16 32))))
                (reordered
                 (relational-solve
                  (relational-admit
                   (relational-compose
                    (list reach-b source-b reach-a source-a)
                    16 16 32)))))
            (check-equal? (element? GerbilAscentFragmentContract reach-a)
                          #t)
            (check-equal? (eq? edge-a edge-b) #f)
            (check-equal? (eq? path-a path-b) #f)
            (check-equal? (same-set? (relational-query result reach-a 'reach)
                                     '((1 2) (2 3) (1 3))) #t)
            (check-equal? (relational-query result reach-b 'reach) '((7 8)))
            (check-equal? (same-set? (relational-query result reach-a 'reach)
                                     (relational-query reordered reach-a 'reach)) #t)
            (check-equal? (same-set? (relational-query result reach-b 'reach)
                                     (relational-query reordered reach-b 'reach)) #t)
            (check-exception (relational-export reach-a 'missing) true)
            (check-exception
             (relational-query result source-a 'reach) true))))
    (poo-flow-test-case "assembled program rejects duplicate instance"
      (let (source (source-fragment '((1 2))))
        (check-exception
         (relational-admit
          (relational-compose (list source source) 8 8 16))
         true)))
    (poo-flow-test-case "fragment export names are unique and instance scoped"
      (let* ((first (source-fragment '((1 2))))
             (second (source-fragment '((3 4)))))
        (check-equal? (eq? (relational-export first 'edge)
                          (relational-export second 'edge)) #f)
        (check-exception (relational-export first 'reach) true)
        (check-exception
         (relational-fragment
          (import)
          (source (edge (from to) '((1 2))))
          (private)
          (export (same edge) (same edge)))
         true)))
    (poo-flow-test-case "fragment constructor freezes supplied export list"
      (let* ((entry (cons 'answer 'original))
             (exports (list entry))
             (fragment (gerbil-ascent-fragment [] [] exports)))
        (set-cdr! entry 'changed)
        (check-equal? (relational-export fragment 'answer) 'original)))
    (poo-flow-test-case "admission and query isolate source and result rows"
      (let* ((row (list 1 2))
             (source (source-fragment (list row)))
             (admission
              (relational-admit
               (relational-compose (list source) 8 8 16))))
        (set-car! row 9)
        (let* ((solution (relational-solve admission))
               (observed (relational-query solution source 'edge)))
          (check-equal? observed '((1 2)))
          (set-car! (car observed) 7)
          (check-equal? (relational-query solution source 'edge)
                        '((1 2)))
          (check-equal? (relational-query
                         (relational-solve admission) source 'edge)
                        '((1 2))))))
    (poo-flow-test-case "admission rejects opaque host callbacks"
      (let* ((source (source-fragment '((1 2))))
             (edge (relational-export source 'edge))
             (callback-rule
              (gerbil-ascent-rule
               (list (gerbil-ascent-atom
                      edge (list (gerbil-ascent-variable '?x)
                                 (gerbil-ascent-variable '?y))))
               (list (gerbil-ascent-guard
                      '(?x) (lambda (_value) #t)))))
             (fragment (gerbil-ascent-fragment [] (list callback-rule))))
        (check-exception
         (relational-admit
         (relational-compose (list source fragment) 8 8 16))
         true)))
    (poo-flow-test-case "admission rebuilds a claimed checked operator"
      (let* ((called #f)
             (source (source-fragment '((1 2) (2 3))))
             (output (selected-fragment))
             (edge (relational-export source 'edge))
             (selected (relational-export output 'selected))
             (x (gerbil-ascent-variable '?x))
             (y (gerbil-ascent-variable '?y))
             (rule
              (gerbil-ascent-rule
               (list (gerbil-ascent-atom selected (list x y)))
               (list (gerbil-ascent-atom edge (list x y))
                     (gerbil-ascent-guard
                      '(?x)
                      (lambda (_value) (set! called #t) #t)
                      (vector 'where 'even? '(?x))))))
             (injected (gerbil-ascent-fragment [] (list rule)))
             (solution
              (relational-solve
               (relational-admit
                (relational-compose
                 (list source output injected) 8 8 16)))))
        (check-equal? called #f)
        (check-equal? (relational-query solution output 'selected)
                      '((2 3)))))
    (poo-flow-test-case "whole-program admission rejects an absent import"
      (let (reach (reach-fragment (gensym 'missing-edge)))
        (check-exception
         (relational-admit (relational-compose (list reach) 8 8 16))
         true)))
    (poo-flow-test-case "solve fails when closure exceeds its fact budget"
      (let* ((source (source-fragment '((1 2) (2 3))))
             (reach (reach-fragment (relational-export source 'edge)))
             (admission
              (relational-admit
               (relational-compose (list source reach) 8 1 16))))
        (check-exception (relational-solve admission) true)
        (check-exception (relational-solve admission) true)))
    (poo-flow-test-case "checked where and compute match finite Scheme model"
      (let* ((input
              (append-map
               (lambda (left)
                 (map (lambda (right) (list left right)) '(0 1 2 3)))
               '(0 1 2 3)))
             (source (source-fragment input))
             (scalar (scalar-fragment
                      (relational-export source 'edge)))
             (solution
              (relational-solve
               (relational-admit
                (relational-compose (list source scalar) 32 32 64))))
             (direct (evaluate-scalar input))
             (expected-even
              (filter (lambda (row) (even? (car row))) input))
             (expected-sum
              (delete-duplicates/hash
               (map (lambda (row)
                      (list (+ (car row) (cadr row))))
                    (filter (lambda (row) (< (car row) (cadr row)))
                            input))))
             (expected-copied
              (delete-duplicates/hash
               (map (lambda (row) (list (car row))) input))))
        (check-equal?
         (same-set? (relational-query solution scalar 'even-edge)
                    expected-even) #t)
        (check-equal?
         (same-set? (relational-query solution scalar 'ordered-sum)
                    expected-sum) #t)
        (check-equal? (same-set? (rows direct 'even-edge)
                                 expected-even) #t)
        (check-equal? (same-set? (rows direct 'ordered-sum)
                                 expected-sum) #t)
        (check-equal? (same-set? (rows direct 'copied-left)
                                 expected-copied) #t)))
    (poo-flow-test-case "checked operator modes reject invalid uses"
      (check-exception
       (relational-fragment
        (import)
        (source (edge (from to) '((1 2))))
        (private (selected (from to)))
        (export (selected selected))
        (rule (selected ?x ?y)
          (edge ?x ?y)
          (where (odd? ?x))))
       true)
      (let* ((source (source-fragment '((1 2))))
             (edge-handle (relational-export source 'edge))
             (bad (unbound-scalar-fragment edge-handle)))
        (check-exception
         (relational-admit (relational-compose (list source bad) 8 8 16))
         true))
      (let* ((source (source-fragment '((bad 2))))
             (scalar (scalar-fragment
                      (relational-export source 'edge)))
             (admission
              (relational-admit
               (relational-compose (list source scalar) 8 8 16))))
        (check-exception (relational-solve admission) true)))
    (poo-flow-test-case "recursive compute budget fails without a result"
      (let* ((fragment (unbounded-count-fragment))
             (admission
              (relational-admit
               (relational-compose (list fragment) 1 8 16))))
        (check-exception (relational-solve admission) true)
        (check-exception (relational-solve admission) true)))
    (poo-flow-test-case "recursive closure equals independent graph model"
      (for-each
       (lambda (edges)
         (let ((actual (rows (evaluate edges) 'path))
               (expected (reference-closure edges)))
           (check-equal? (same-set? actual expected) #t)))
       '(() ((1 2)) ((1 2) (2 3) (3 1))
         ((1 2) (1 2) (2 3) (4 5))
         ((1 1) (1 2) (2 2)))))
    (poo-flow-test-case "all 64 simple directed graphs on three nodes"
      (let (graphs
            (foldl
             (lambda (edge sets)
               (append sets
                       (map (lambda (set) (cons edge set)) sets)))
             (list [])
             '((1 2) (1 3) (2 1) (2 3) (3 1) (3 2))))
        (check-equal? (length graphs) 64)
        (for-each
         (lambda (edges)
           (let* ((source (source-fragment edges))
                  (reach (reach-fragment
                          (relational-export source 'edge)))
                  (solution
                   (relational-solve
                    (relational-admit
                     (relational-compose (list source reach)
                                         32 32 64))))
                  (expected (reference-closure edges)))
             (check-equal?
              (same-set? (rows (evaluate edges) 'path) expected) #t)
             (check-equal?
              (same-set? (relational-query solution reach 'reach)
                         expected) #t)))
         graphs)))
    (poo-flow-test-case "new source snapshot does not mutate old result"
      (let* ((before (evaluate '((1 2) (2 3))))
             (after (evaluate '((1 2)))))
        (check-equal? (same-set? (rows before 'path)
                                 '((1 2) (2 3) (1 3))) #t)
        (check-equal? (same-set? (rows after 'path) '((1 2))) #t)
        (check-equal? (length (rows before 'path)) 3)))
    (poo-flow-test-case "repeated variables and scalar literals"
      (let* ((result
              (gerbil-ascent-evaluate-program
               (relational-program
                (relation edge (from to) '((1 1) (1 2) (2 3)))
                (relation loop (node))
                (relation from-one (node))
                (rule (loop ?x) (edge ?x ?x))
                (rule (from-one ?y) (edge 1 ?y))
                (limits 8 8 16)))))
        (check-equal? (rows result 'loop) '((1)))
        (check-equal? (same-set? (rows result 'from-one)
                                 '((1) (2))) #t)))
    (poo-flow-test-case "source replacement retains scalar contract"
      (let (session
            (gerbil-ascent-open-session
             (relational-program
              (relation edge (from to) '((1 2)))
              (limits 8 8 16))))
        (check-exception
         (gerbil-ascent-session-replace-source!
          session 'edge '((1 "mutable")))
         true)))
    (poo-flow-test-case "unsafe head, invalid source and budget fail"
      (check-exception
       (gerbil-ascent-evaluate-program
        (relational-program
         (relation edge (from to) '((1 2)))
         (relation path (from to))
         (rule (path ?x ?z) (edge ?x ?y))
         (limits 8 8 16)))
       true)
      (check-exception
       (relational-program
        (relation edge (from to) '((1 "mutable")))
        (limits 8 8 16))
       true)
      (check-exception
       (eval
        '(begin
           (import :gerbil-ascent/program/scheme-language)
           (relational-program
            (relation edge (from to) '((1 2)))
            (relation path (from to))
            (rule (path plain ?y) (edge ?x ?y))
            (limits 8 8 16))))
       true)
      (check-exception (evaluate '((1 2) (2 3)) 1) true))))
