;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :gerbil-ascent/program/funs gerbil-ascent-rule-strata)
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

(def ascent-strata-test
  (test-suite "ASCENT SCC stratification"
    (poo-flow-test-case "strict incoming edges lift every member of a positive SCC"
      (check-equal?
       (gerbil-ascent-rule-strata
        (ascent-strata-rule-plans
         (list (vector 1 0 'negation)
               (vector 2 1 'atom)
               (vector 1 2 'atom)
               (vector 3 2 'aggregate)))
        4 '#(relation relation relation relation))
       '#(0 1 1 2)))
    (poo-flow-test-case "all three-node graphs preserve minimum strata and cycle diagnostics"
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
    (poo-flow-test-case "empty declarations and duplicate edges retain their strata"
      (check-equal? (gerbil-ascent-rule-strata [] 0 '#()) '#())
      (check-strata
       (list (vector 1 0 'negation) (vector 1 0 'negation)
             (vector 2 1 'atom) (vector 2 1 'atom))
       '#(relation relation relation)))))
