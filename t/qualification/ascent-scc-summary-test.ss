;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/core/dependency-graph gerbil-ascent-graph-components)
        (only-in :gerbil-ascent/t/qualification/ascent-graph-fixture
                 ascent-reference-graph-components)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-program-summary)
        (only-in :gerbil-ascent/program/syntax ascent))

(export ascent-scc-summary-test main)

(def (sample-program)
  (ascent
   (relation seed (value))
   (relation copied (value))
   (relation left (value))
   (relation right (value))
   (relation final_rel (value))
   ((copied x) <-- (seed x))
   ((left x) <-- (right x))
   ((right x) <-- (left x))
   ((final_rel x) <-- (left x))
   (bounds 16 16 32)))

(def (sccs)
  (.ref (gerbil-ascent-program-summary (sample-program)) 'sccs))

(def (members scc)
  (.ref scc 'dynamic-relations))

(def ascent-scc-summary-test
  (test-suite "ASCENT rule dependency SCC summary"
    (poo-flow-test-case "explicit DFS preserves exact SCC order for all three-node graphs"
      (for-each
       (lambda (mask)
         (let (graph (make-vector 3 []))
           (for-each
            (lambda (edge)
              (unless (zero? (bitwise-and mask (arithmetic-shift 1 edge)))
                (let (source (quotient edge 3))
                  (vector-set! graph source
                    (cons (modulo edge 3) (vector-ref graph source))))))
            (iota 9))
           (for-each
            (lambda (variant)
              (let (expected (ascent-reference-graph-components variant))
                (check-equal? (gerbil-ascent-graph-components variant) expected)
                (check-equal? (gerbil-ascent-graph-components variant) expected)))
            (list graph
                  (vector-map reverse graph)
                  (vector-map (lambda (edges) (append edges edges)) graph)))))
       (iota 512)))
    (poo-flow-test-case "deep chains and cycles retain edges and source order"
      (let* ((count 20000)
             (vertices (iota count))
             (chain (list->vector
                     (map (lambda (n)
                            (if (= (+ n 1) count) [] (list (+ n 1)))) vertices)))
             (snapshot (map (lambda (edges) (append edges []))
                            (vector->list chain))))
        (check-equal? (gerbil-ascent-graph-components '#()) [])
        (check-equal? (gerbil-ascent-graph-components chain) (map list vertices))
        (check-equal? (vector->list chain) snapshot)
        (vector-set! chain (- count 1) '(0))
        (check-equal? (gerbil-ascent-graph-components chain) (list vertices))
        (check-equal? (vector-ref chain (- count 1)) '(0))))
    (poo-flow-test-case "recursive pair and acyclic rules have distinct SCCs"
      (let (components (sccs))
        (check-equal? (length components) 3)
        (check-equal?
         (length (filter (lambda (scc) (.ref scc 'is-looping)) components))
         1)
        (check-equal?
         (length (filter (lambda (scc)
                           (and (= (length (members scc)) 2)
                                (member 'left (members scc))
                                (member 'right (members scc))))
                         components))
         1)
        (check-equal?
         (length (filter (lambda (scc)
                           (equal? (members scc) '(copied))) components))
         1)
        (check-equal?
         (length (filter (lambda (scc)
                           (equal? (members scc) '(final_rel))) components))
         1)))))

(def (main . args)
  (unless (null? args) (error "ASCENT SCC summary takes no arguments"))
  (for-each
   (lambda (scc)
     (display "SCC")
     (display #\tab)
     (display (if (.ref scc 'is-looping) "true" "false"))
     (for-each
      (lambda (name)
        (display #\tab)
        (display name))
      (members scc))
     (newline))
   (sccs))
  (force-output))
