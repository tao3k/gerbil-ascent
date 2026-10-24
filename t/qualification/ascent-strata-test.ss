;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite test-case)
        (only-in :gerbil-ascent/core/rule-semantics gerbil-ascent-rule-strata)
        (only-in :gerbil-ascent/t/qualification/ascent-strata-fixture
                 ascent-reference-rule-strata ascent-strata-rule-plans))
(export ascent-strata-test)

(def (strata-outcome solve plans kinds)
  (with-catch
   (lambda (failure) (cons 'error (error-message failure)))
   (lambda () (vector->list (solve plans (vector-length kinds) kinds)))))

(def (graph-edges mask)
  (filter-map
   (lambda (edge)
     (and (not (zero? (bitwise-and mask (arithmetic-shift 1 edge))))
          (vector (quotient edge 3) (modulo edge 3) 'atom)))
   (iota 9)))

(def (check-strata edges kinds)
  (let (plans (ascent-strata-rule-plans edges))
    (check-equal? (strata-outcome gerbil-ascent-rule-strata plans kinds)
                  (strata-outcome ascent-reference-rule-strata plans kinds))))


;;; Independent finite oracle: enumerate all 27 three-node level assignments.
;;; No SCC traversal or relaxation is used to construct the expected answer.
;;; A feasible three-node weighted graph has a minimal labeling in 0..2:
;;; strict cycles are infeasible, and a simple condensation path has <=2 edges.
(def (strata-labels)
  (map (lambda (code)
         (vector (modulo code 3) (modulo (quotient code 3) 3)
                 (quotient code 9)))
       (iota 27)))

(def (valid-strata? edges kinds levels)
  (andmap
   (lambda (edge)
     (let* ((head (vector-ref edge 0)) (source (vector-ref edge 1))
            (kind (vector-ref edge 2))
            (weight (if (or (not (eq? kind 'atom))
                            (and (eq? (vector-ref kinds source) 'lattice)
                                 (eq? (vector-ref kinds head) 'relation))) 1 0)))
       (<= (+ (vector-ref levels source) weight) (vector-ref levels head))))
   edges))

(def (check-enumerated-strata edges kinds)
  (let* ((valid (filter (lambda (levels) (valid-strata? edges kinds levels))
                        (strata-labels)))
         (actual (strata-outcome gerbil-ascent-rule-strata
                                 (ascent-strata-rule-plans edges) kinds)))
    (if (null? valid)
      (check-equal? (car actual) 'error)
      (check-equal? actual
                    (map (lambda (key)
                           (apply min (map (lambda (levels) (vector-ref levels key)) valid)))
                         (iota 3))))))

(def (relation-kinds mask)
  (list->vector
   (map (lambda (key)
          (if (zero? (bitwise-and mask (arithmetic-shift 1 key))) 'relation 'lattice))
        (iota 3))))

(def ascent-strata-test
  (test-suite "ASCENT SCC stratification"
    (test-case "strict incoming edges lift every member of a positive SCC"
      (check-equal?
       (gerbil-ascent-rule-strata
        (ascent-strata-rule-plans
         (list (vector 1 0 'negation)
               (vector 2 1 'atom)
               (vector 1 2 'atom)
               (vector 3 2 'aggregate)))
        4 '#(relation relation relation relation))
       '#(0 1 1 2)))
    (test-case "all three-node graphs preserve minimum strata and cycle diagnostics"
      (for-each
       (lambda (mask)
         (let (edges (graph-edges mask))
           (check-strata edges '#(relation relation relation))
           (for-each
            (lambda (strict-edge)
              (for-each
               (lambda (kind)
                 (check-strata
                  (map (lambda (edge)
                         (if (eq? edge strict-edge)
                           (vector (vector-ref edge 0) (vector-ref edge 1) kind)
                           edge))
                       edges)
                  '#(relation relation relation)))
               '(negation aggregate)))
            edges)
           (check-strata
            (map (lambda (edge)
                   (vector (vector-ref edge 0) (vector-ref edge 1)
                           (if (even? (vector-ref edge 0)) 'aggregate 'negation)))
                 edges)
            '#(relation relation relation))
           (check-strata edges '#(relation lattice relation))
           (check-strata edges '#(lattice relation lattice))))
       (iota 512)))
    (test-case "enumerated labels independently validate strict edges and SCC minima"
      (for-each
       (lambda (mask)
         (let (edges (graph-edges mask))
           (for-each (lambda (kinds-mask)
                       (check-enumerated-strata edges (relation-kinds kinds-mask)))
                     (iota 8))
           (for-each
            (lambda (selected)
              (for-each
               (lambda (kind)
                 (check-enumerated-strata
                  (map (lambda (edge)
                         (if (eq? edge selected)
                           (vector (vector-ref edge 0) (vector-ref edge 1) kind) edge))
                       edges)
                  '#(relation relation relation)))
               '(negation aggregate)))
            edges))
         (when (zero? (modulo (+ mask 1) 64))
           (displayln "[strata-oracle] completed graphs=" (+ mask 1))))
       (iota 512)))
    (test-case "multi-head projection ignores non-reading clauses"
      (check-equal?
       (gerbil-ascent-rule-strata
        (list (vector (list (vector 1 []) (vector 2 []))
                      (list (vector 'atom (vector 0 []))
                            (vector 'guard #f) (vector 'generator #f) (vector 'binding #f))))
        3 '#(lattice relation relation))
       '#(0 1 1)))
    (test-case "empty declarations and duplicate edges retain their strata"
      (check-equal? (gerbil-ascent-rule-strata [] 0 '#()) '#())
      (check-strata
       (list (vector 1 0 'negation) (vector 1 0 'negation)
             (vector 2 1 'atom) (vector 2 1 'atom))
       '#(relation relation relation)))))
