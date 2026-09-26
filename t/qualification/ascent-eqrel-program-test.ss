;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :clan/poo/object .o .ref)
        (only-in :poo-flow-foundation/module-system/observability/testing-case
                 poo-flow-test-case)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-hash-index-provider
                 gerbil-ascent-set-storage-provider
                 gerbil-ascent-eqrel-storage-provider
                 gerbil-ascent-trrel-storage-provider
                 gerbil-ascent-trrel-uf-storage-provider)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-program
                 gerbil-ascent-evaluate-program
                 gerbil-ascent-variable gerbil-ascent-atom
                 gerbil-ascent-rule)
        (only-in :gerbil-ascent/t/qualification/ascent-eqrel-program-fixture
                 ascent-eqrel-fixture-evaluate
                 ascent-storage-fixture-evaluate))

(export ascent-eqrel-program-test)

(def ascent-eqrel-program-test
  (test-suite "ASCENT BYODS equivalence storage"
    (poo-flow-test-case "binary eqrel yields reflexive symmetric transitive facts"
      (let (rows
            ((.ref (ascent-eqrel-fixture-evaluate
                    '((1 2) (2 3)) []) 'rows-of)
             'binary-output))
        (check-equal? (length rows) 9)
        (check-equal? (not (not (member '(1 3) rows))) #t)
        (check-equal? (not (not (member '(3 1) rows))) #t)
        (check-equal? (not (not (member '(2 2) rows))) #t)))
    (poo-flow-test-case "ternary eqrel isolates leading groups"
      (let (rows
            ((.ref (ascent-eqrel-fixture-evaluate
                    [] '((0 1 2) (1 2 3))) 'rows-of)
             'grouped-output))
        (check-equal? (length rows) 8)
        (check-equal? (member '(0 1 3) rows) #f)
        (check-equal? (not (not (member '(0 2 1) rows))) #t)
        (check-equal? (not (not (member '(1 3 2) rows))) #t)))
    (poo-flow-test-case "source eqrel facts are materialized at initialization"
      (let* ((program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation
                      'eq 2 '((1 2) (2 3))
                      gerbil-ascent-hash-index-provider
                      gerbil-ascent-eqrel-storage-provider))
               [] 16 16 32))
             (rows ((.ref (gerbil-ascent-evaluate-program program) 'rows-of)
                    'eq)))
        (check-equal? (length rows) 9)
        (check-equal? (not (not (member '(3 1) rows))) #t)))
    (poo-flow-test-case "trrel preserves directed reachability without reflexive facts"
      (let (rows
            ((.ref (ascent-storage-fixture-evaluate
                    '((1 2) (2 3)) []
                    gerbil-ascent-trrel-storage-provider) 'rows-of)
             'binary-output))
        (check-equal? (length rows) 3)
        (check-equal? (not (not (member '(1 3) rows))) #t)
        (check-equal? (member '(3 1) rows) #f)
        (check-equal? (member '(1 1) rows) #f)))
    (poo-flow-test-case "trrel excludes cyclic self reachability"
      (let (rows
            ((.ref (ascent-storage-fixture-evaluate
                    '((1 2) (2 3) (3 1)) []
                    gerbil-ascent-trrel-storage-provider) 'rows-of)
             'binary-output))
        (check-equal? (length rows) 6)
        (check-equal? (member '(2 2) rows) #f)))
    (poo-flow-test-case "trrel keeps explicit reflexive facts"
      (let (rows
            ((.ref (ascent-storage-fixture-evaluate
                    '((1 1)) [] gerbil-ascent-trrel-storage-provider)
                   'rows-of)
             'binary-output))
        (check-equal? rows '((1 1)))))
    (poo-flow-test-case "trrel_uf exposes reflexive transitive closure"
      (let (rows
            ((.ref (ascent-storage-fixture-evaluate
                    '((1 2) (2 3)) []
                    gerbil-ascent-trrel-uf-storage-provider) 'rows-of)
             'binary-output))
        (check-equal? (length rows) 6)
        (check-equal? (not (not (member '(1 1) rows))) #t)
        (check-equal? (not (not (member '(3 3) rows))) #t)
        (check-equal? (member '(3 1) rows) #f)))
    (poo-flow-test-case "invalid storage method output fails at the boundary"
      (check-exception
       (gerbil-ascent-evaluate-program
        (gerbil-ascent-program
         (list (gerbil-ascent-relation
                'broken 2 '((1 2))
                gerbil-ascent-hash-index-provider
                (.o (:: @ gerbil-ascent-set-storage-provider)
                    (.extend-rows
                     (lambda (_all _pending _row _budget) 'broken)))))
         [] 4 4 4))
       true))
    (poo-flow-test-case "eqrel output stays within the program fact budget"
      (check-exception
       (ascent-eqrel-fixture-evaluate
        '((1 2) (2 3) (3 4) (4 5) (5 6) (6 7) (7 8)
          (8 9) (9 10) (10 11) (11 12) (12 13) (13 14)
          (14 15) (15 16) (16 17) (17 18) (18 19))
        [])
       true))
    (poo-flow-test-case "materialized source facts count toward total output"
      (let* ((x (gerbil-ascent-variable 'x))
             (y (gerbil-ascent-variable 'y))
             (program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation
                      'eq 2 '((1 2) (2 3))
                      gerbil-ascent-hash-index-provider
                      gerbil-ascent-eqrel-storage-provider)
                     (gerbil-ascent-relation 'copied 2 []))
               (list (gerbil-ascent-rule
                      (list (gerbil-ascent-atom 'copied (list x y)))
                      (list (gerbil-ascent-atom 'eq (list x y)))))
               4 16 12)))
        (check-exception (gerbil-ascent-evaluate-program program) true)))))
