;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? check-exception test-case test-suite)
        (only-in :gerbil-ascent/candidate/types make-reasoning-candidate)
        (only-in :gerbil-ascent/candidate/reasoning reasoning-source-snapshot)
        (only-in :gerbil-ascent/candidate/provenance-graph
                 candidate-positive-provenance candidate-verify-positive-provenance
                 positive-provenance-status positive-provenance-alternatives
                 candidate-open-provenance-maintenance provenance-maintenance-rows
                 candidate-provenance-withdraw!))
(import (only-in :gerbil-ascent/program/scheme-language
                 relational-program relational-admit relational-solve relational-query-name))

(def corpus-edges '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))
(def (edges-for-mask mask)
  (filter-map (lambda (edge position)
                (and (odd? (quotient mask (expt 2 position))) edge))
              corpus-edges '(0 1 2 3 4 5)))

;;; Independent matrix closure, not a relational/provenance evaluator.
(def (matrix-closure edges)
  (let (matrix (make-vector 9 #f))
    (for-each (lambda (edge)
                (vector-set! matrix (+ (* 3 (car edge)) (cadr edge)) #t)) edges)
    (for-each
     (lambda (k)
       (for-each
        (lambda (i)
          (for-each (lambda (j)
                      (when (and (vector-ref matrix (+ (* 3 i) k))
                                 (vector-ref matrix (+ (* 3 k) j)))
                        (vector-set! matrix (+ (* 3 i) j) #t))) '(0 1 2)))
        '(0 1 2))) '(0 1 2))
    (filter-map (lambda (position)
                  (and (vector-ref matrix position)
                       (list (quotient position 3) (modulo position 3)))) (iota 9))))

(def (native-paths edges)
  (relational-query-name
   (relational-solve
    (relational-admit
     (relational-program
      (relation edge (from to) edges)
      (relation path (from to) '())
      (rule (path ?x ?y) (edge ?x ?y))
      (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
      (limits 16 64 128)))) 'path))

(def (check-row-set actual expected)
  (check-equal? (length actual) (length expected))
  (for-each (lambda (row) (check-equal? (and (member row actual) #t) #t)) expected))

(export scheme-provenance-graph-test)

(def (recursive-provenance-spec)
  (make-reasoning-candidate
   '((p . 1)) []
   (list (vector '(p ?x) '((s ?x)) 10)
         (vector '(p ?x) '((p ?x)) 11))
   (vector '(p ?x) 12) '(8 16 32)))

(def scheme-provenance-graph-test
  (test-suite "Complete grounded provenance and deletion"
    (test-case "recursive provenance retains every source and cyclic alternative"
      (let* ((snapshot (reasoning-source-snapshot 'complete-graph 1
                                                  '((s 1 ((1) (1))))))
             (spec (recursive-provenance-spec))
             (graph (candidate-positive-provenance
                     snapshot spec 'program 'complete '((1)) 64)))
        (check-equal? (positive-provenance-status graph) 'complete)
        (check-equal? (length (positive-provenance-alternatives graph)) 4)
        (check-equal? (candidate-verify-positive-provenance
                      snapshot spec 'program 'complete '((1)) graph 64) #t)
        (check-equal? (member '(1 rule (1 11) (1))
                             (positive-provenance-alternatives graph))
                      '((1 rule (1 11) (1))))))
    (test-case "a recursive cycle without a founded source proves no row"
      (let* ((snapshot (reasoning-source-snapshot 'empty-cycle 1 '((s 1 ()))))
             (spec (recursive-provenance-spec))
             (graph (candidate-positive-provenance
                     snapshot spec 'program 'complete [] 64)))
        (check-equal? (positive-provenance-status graph) 'complete)
        (check-equal? (positive-provenance-alternatives graph) [])
        (check-equal? (candidate-verify-positive-provenance
                      snapshot spec 'program 'complete [] graph 64) #t)))
    (test-case "complete provenance cannot omit an alternative or exceed its cap"
      (let* ((snapshot (reasoning-source-snapshot 'tamper-graph 1 '((s 1 ((1))))))
             (spec (recursive-provenance-spec))
             (graph (candidate-positive-provenance
                     snapshot spec 'program 'complete '((1)) 64))
             (bounded (candidate-positive-provenance
                       snapshot spec 'program 'complete '((1)) 64 2)))
        (check-equal? (positive-provenance-status bounded) 'bounded)
        (check-equal? (positive-provenance-alternatives bounded) [])
        (set-cdr! (positive-provenance-alternatives graph) [])
        (check-equal? (candidate-verify-positive-provenance
                      snapshot spec 'program 'complete '((1)) graph 64) #f)
        (check-equal? (candidate-verify-positive-provenance
                      snapshot spec 'different 'complete '((1)) graph 64) #f)))
    (test-case "grounded DRed restores alternate support and removes the last cyclic support"
      (let* ((snapshot (reasoning-source-snapshot 'deletion 1 '((s 1 ((1) (1))))))
             (spec (recursive-provenance-spec))
             (graph (candidate-positive-provenance
                     snapshot spec 'program 'complete '((1)) 64))
             (state (candidate-open-provenance-maintenance
                     snapshot spec 'program 'complete '((1)) graph 64)))
        (let-values (((rows work) (candidate-provenance-withdraw! state '((s 1)))))
          (check-equal? rows '((1)))
          (check-equal? (> work 0) #t))
        (let-values (((rows work) (candidate-provenance-withdraw! state '((s 2)))))
          (check-equal? rows [])
          (check-equal? (> work 0) #t))
        (let* ((fresh (reasoning-source-snapshot 'deletion 2 '((s 1 ()))))
               (fresh-graph (candidate-positive-provenance
                             fresh spec 'program 'complete [] 64)))
          (check-equal? (positive-provenance-status fresh-graph) 'complete)
          (check-equal? (provenance-maintenance-rows state) []))))
    (test-case "failed grounded deletion preserves the published rows and source state"
      (let* ((snapshot (reasoning-source-snapshot 'deletion-rollback 1 '((s 1 ((1))))))
             (spec (recursive-provenance-spec))
             (graph (candidate-positive-provenance
                     snapshot spec 'program 'complete '((1)) 64))
             (state (candidate-open-provenance-maintenance
                     snapshot spec 'program 'complete '((1)) graph 64)))
        (check-exception (candidate-provenance-withdraw! state '((s 1)) 1) true)
        (check-equal? (provenance-maintenance-rows state) '((1)))
        (check-exception (candidate-provenance-withdraw! state '((unknown 1))) true)
        (check-equal? (provenance-maintenance-rows state) '((1)))
        (let-values (((rows work) (candidate-provenance-withdraw! state '((s 1)))))
          (check-equal? rows []))))
    (test-case "all sixty-four graphs preserve complete alternatives and every withdrawal"
      (for-each
       (lambda (mask)
         (let* ((edges (edges-for-mask mask))
                (expected (matrix-closure edges))
                (native (native-paths edges))
                (snapshot (reasoning-source-snapshot 'graph-corpus mask
                            (list (list 'edge 2 edges))))
                (spec (make-reasoning-candidate
                       '((path . 2)) []
                       (list (vector '(path ?x ?y) '((edge ?x ?y)) 10)
                             (vector '(path ?x ?z) '((path ?x ?y) (edge ?y ?z)) 11))
                       (vector '(path ?x ?y) 12) '(16 64 128)))
                (graph (candidate-positive-provenance
                        snapshot spec 'corpus 'complete native 10000))
                (state (candidate-open-provenance-maintenance
                        snapshot spec 'corpus 'complete native graph 10000))
                (recursive-alternatives
                 (apply + (map (lambda (path)
                                 (length (filter (lambda (edge)
                                                   (= (cadr path) (car edge))) edges)))
                               expected))))
           (check-row-set native expected)
           (check-equal? (positive-provenance-status graph) 'complete)
           (check-equal? (length (positive-provenance-alternatives graph))
                         (+ (* 2 (length edges)) recursive-alternatives))
           (displayln "PROVENANCE-CHECKED " mask " complete") (force-output)
           (let loop ((remaining edges) (position 1))
             (when (pair? remaining)
               (let-values (((rows work)
                             (candidate-provenance-withdraw!
                              state (list (list 'edge position)))))
                 (check-row-set rows (matrix-closure (cdr remaining)))
                 (check-row-set rows (native-paths (cdr remaining)))
                 (check-equal? (> work 0) #t)
                 (displayln "PROVENANCE-CHECKED " mask " withdrawal " position)
                 (force-output))
               (loop (cdr remaining) (+ position 1))))))
       (iota 64)))))
