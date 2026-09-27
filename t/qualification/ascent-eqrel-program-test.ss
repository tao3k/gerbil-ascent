;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :clan/poo/object .o .ref)
        (only-in :core/observability/testing-case
                 poo-flow-test-case)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-hash-index-provider
                 gerbil-ascent-set-storage-provider
                 gerbil-ascent-eqrel-storage-provider
                 gerbil-ascent-trrel-storage-provider
                 gerbil-ascent-trrel-uf-storage-provider
                 gerbil-ascent-storage-make-state
                 gerbil-ascent-storage-extend)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-program
                 gerbil-ascent-evaluate-program
                 gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-run
                 gerbil-ascent-variable gerbil-ascent-atom
                 gerbil-ascent-rule)
        (only-in :gerbil-ascent/t/qualification/ascent-eqrel-program-fixture
                 ascent-eqrel-fixture-evaluate
                 ascent-storage-fixture-evaluate)
        (only-in :gerbil-ascent/t/qualification/ascent-byods-query-fixture
                 ascent-byods-query-program
                 ascent-byods-query-evaluate))

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
    (poo-flow-test-case "eqrel component state is private to concurrent runs"
      (let* ((program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation
                      'eq 2 '((1 2) (2 3))
                      gerbil-ascent-hash-index-provider
                      gerbil-ascent-eqrel-storage-provider))
               [] 16 16 32))
             (workers
              (map (lambda (_)
                     (spawn
                      (lambda ()
                        ((.ref (gerbil-ascent-evaluate-program program)
                               'rows-of) 'eq))))
                   (iota 4)))
             (results (map thread-join! workers)))
        (check-equal? (map length results) '(9 9 9 9))
        (check-equal?
         (andmap (lambda (rows) (not (not (member '(1 3) rows)))) results)
         #t)))
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
    (poo-flow-test-case "directed closure state is private to concurrent runs"
      (let* ((edges '((1 2) (2 3)))
             (program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation
                      'tr 2 edges
                      gerbil-ascent-hash-index-provider
                      gerbil-ascent-trrel-storage-provider)
                     (gerbil-ascent-relation
                      'uf 2 edges
                      gerbil-ascent-hash-index-provider
                      gerbil-ascent-trrel-uf-storage-provider))
               [] 16 16 32))
             (workers
              (map (lambda (_)
                     (spawn
                      (lambda ()
                        (let (rows-of
                              (.ref (gerbil-ascent-evaluate-program program)
                                    'rows-of))
                          (list (rows-of 'tr) (rows-of 'uf))))))
                   (iota 4)))
             (results (map thread-join! workers)))
        (check-equal? (map (lambda (rows) (length (car rows))) results)
                      '(3 3 3 3))
        (check-equal? (map (lambda (rows) (length (cadr rows))) results)
                      '(6 6 6 6))))
    (poo-flow-test-case "BYODS relations join with typed group and wanted facts"
      (let* ((result (ascent-byods-query-evaluate
                      '(("alpha" 1 2) ("alpha" 2 3)
                        ("beta" 1 2))
                      '(("alpha" 3) ("beta" 2))))
             (rows-of (.ref result 'rows-of)))
        (check-equal? (length (rows-of 'eq-match)) 5)
        (check-equal? (length (rows-of 'tr-match)) 3)
        (check-equal? (length (rows-of 'uf-match)) 5)
        (check-equal? (not (not (member '("alpha" 1 3)
                                        (rows-of 'tr-match)))) #t)
        (check-equal? (member '("beta" 3 2) (rows-of 'eq-match)) #f)))
    (poo-flow-test-case "BYODS rules merge independently sourced path segments"
      (let* ((result (ascent-byods-query-evaluate
                      '(("alpha" 1 2) ("beta" 1 2))
                      '(("alpha" 3) ("beta" 1))
                      '(("alpha" 2 3) ("beta" 2 1))))
             (rows-of (.ref result 'rows-of)))
        (check-equal? (not (not (member '("alpha" 1 3)
                                        (rows-of 'eq-match)))) #t)
        (check-equal? (not (not (member '("alpha" 1 3)
                                        (rows-of 'tr-match)))) #t)
        (check-equal? (not (not (member '("beta" 2 1)
                                        (rows-of 'uf-match)))) #t)
        (check-equal? (length (rows-of 'eq-match)) 5)
        (check-equal? (length (rows-of 'tr-match)) 3)
        (check-equal? (length (rows-of 'uf-match)) 5)))
    (poo-flow-test-case "eqrel delta joins two producer rules in one group"
      (let* ((wanted '(("alpha" 3)))
             (first '(("alpha" 1 2)))
             (second '(("alpha" 2 3)))
             (split (ascent-byods-query-evaluate first wanted second))
             (reversed (ascent-byods-query-evaluate second wanted first))
             (combined (ascent-byods-query-evaluate
                        (append first second) wanted)))
        (for-each
         (lambda (result)
           (let (rows ((.ref result 'rows-of) 'eq-match))
             (check-equal? (length rows) 3)
             (check-equal? (not (not (member '("alpha" 1 3) rows))) #t)))
         (list split reversed combined))))
    (poo-flow-test-case "BYODS session joins a later source producer"
      (let* ((session
              (gerbil-ascent-open-session
               (ascent-byods-query-program
                '(("alpha" 1 2)) '(("alpha" 3)))))
             (first (gerbil-ascent-session-run session)))
        (check-equal? ((.ref first 'rows-of) 'eq-match) [])
        (gerbil-ascent-session-append-source!
         session 'seed-extra '("alpha" 2 3))
        (let ((second (gerbil-ascent-session-run session))
              (fresh (ascent-byods-query-evaluate
                      '(("alpha" 1 2)) '(("alpha" 3))
                      '(("alpha" 2 3)))))
          (for-each
           (lambda (name)
             (check-equal?
              (length ((.ref second 'rows-of) name))
              (length ((.ref fresh 'rows-of) name))))
           '(eq-match tr-match uf-match))
          (check-equal? (not (not (member '("alpha" 1 3)
                                          ((.ref second 'rows-of) 'eq-match))))
                        #t)
          (check-equal? ((.ref first 'rows-of) 'eq-match) []))))
    (poo-flow-test-case "BYODS providers emit only new rows across edge prefixes"
      (for-each
       (lambda (provider edges expected-sizes)
         (let* ((state (gerbil-ascent-storage-make-state provider))
                (all []))
           (for-each
            (lambda (edge expected-size)
              (let (new-rows
                    (gerbil-ascent-storage-extend
                     provider state all [] edge 32))
                (for-each
                 (lambda (row)
                   (check-equal? (member row all) #f))
                 new-rows)
                (set! all (append new-rows all))
                (check-equal? (length all) expected-size)))
            edges expected-sizes)))
       (list gerbil-ascent-eqrel-storage-provider
             gerbil-ascent-trrel-storage-provider
             gerbil-ascent-trrel-uf-storage-provider)
       '((("alpha" 1 2) ("alpha" 2 3) ("alpha" 1 3)
          ("beta" 1 2) ("alpha" 3 4))
         ((1 2) (2 3) (3 1))
         ((1 2) (2 3) (3 1)))
       '((4 9 9 13 20) (1 3 6) (3 6 9))))
    (poo-flow-test-case "BYODS budget rejection leaves provider state reusable"
      (for-each
       (lambda (provider first rejected retry first-budget retry-budget)
         (let* ((state (gerbil-ascent-storage-make-state provider))
                (initial (gerbil-ascent-storage-extend
                          provider state [] [] first first-budget))
                (fresh (gerbil-ascent-storage-make-state provider)))
           (check-equal?
            (gerbil-ascent-storage-extend provider state initial [] first 0)
            [])
           (check-exception
            (gerbil-ascent-storage-extend
             provider state initial [] rejected 0)
            true)
           (check-equal?
            (gerbil-ascent-storage-extend
             provider state initial [] retry retry-budget)
            (begin
              (gerbil-ascent-storage-extend
               provider fresh [] [] first first-budget)
              (gerbil-ascent-storage-extend
               provider fresh initial [] retry retry-budget)))))
       (list gerbil-ascent-eqrel-storage-provider
             gerbil-ascent-trrel-storage-provider
             gerbil-ascent-trrel-uf-storage-provider)
       '((1 2) (1 2) (1 2))
       '((2 3) (2 3) (2 3))
       '((4 5) (4 5) (4 5))
       '(4 1 3)
       '(4 1 3)))
    (poo-flow-test-case "BYODS session can continue after a rejected append"
      (for-each
       (lambda (provider limit first rejected retry)
         (let* ((make-program
                 (lambda (rows)
                   (gerbil-ascent-program
                    (list (gerbil-ascent-relation
                           'stored 2 rows
                           gerbil-ascent-hash-index-provider provider))
                    [] 4 8 limit)))
                (session (gerbil-ascent-open-session
                          (make-program (list first)))))
           (gerbil-ascent-session-run session)
           (check-exception
            (gerbil-ascent-session-append-source! session 'stored rejected)
            true)
           (gerbil-ascent-session-append-source! session 'stored retry)
           (let ((actual ((.ref (gerbil-ascent-session-run session) 'rows-of)
                          'stored))
                 (expected ((.ref (gerbil-ascent-evaluate-program
                                   (make-program (list first retry)))
                                  'rows-of)
                            'stored)))
             (check-equal? (length actual) (length expected))
             (for-each (lambda (row)
                         (check-equal? (not (not (member row actual))) #t))
                       expected))))
       (list gerbil-ascent-eqrel-storage-provider
             gerbil-ascent-trrel-storage-provider
             gerbil-ascent-trrel-uf-storage-provider)
       '(5 2 4)
       '((1 2) (1 2) (1 2))
       '((2 3) (2 3) (2 3))
       '((4 4) (4 5) (4 4))))
    (poo-flow-test-case "invalid storage method output fails at the boundary"
      (check-exception
       (gerbil-ascent-evaluate-program
        (gerbil-ascent-program
         (list (gerbil-ascent-relation
                'broken 2 '((1 2))
                gerbil-ascent-hash-index-provider
                (.o (:: @ gerbil-ascent-set-storage-provider)
                    (.extend-rows
                     (lambda (_state _all _pending _row _budget) 'broken)))))
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
