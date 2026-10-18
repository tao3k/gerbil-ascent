;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite test-case)
        (only-in :clan/poo/object .o .ref)
        (only-in :gerbil-ascent/program/analysis gerbil-ascent-program-schema)
        (only-in :gerbil-ascent/program/planning gerbil-ascent-prepare-program)
        (only-in :gerbil-ascent/core/positive-plan gerbil-ascent-index-key/terms)
        (only-in :gerbil-ascent/t/qualification/ascent-index-reference-evaluate
                 ascent-index-reference-evaluate-program)
        (only-in :gerbil-ascent/t/qualification/ascent-index-program-fixture
                 ascent-index-fixture-program
                 ascent-composite-index-fixture-program
                 ascent-lattice-index-fixture-program
                 ascent-index-alist-provider)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program gerbil-ascent-relation
                 gerbil-ascent-program gerbil-ascent-rule gerbil-ascent-atom
                 gerbil-ascent-variable gerbil-ascent-literal
                 gerbil-ascent-expression gerbil-ascent-guard
                 gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-run))

(export ascent-index-program-test)

(def ascent-index-program-test
  (test-suite "ASCENT indexed relation access"
    (test-case "prepared expression keys preserve provider and callback order"
      (let* ((events [])
             (provider
              (.o (:: @ gerbil-ascent-hash-index-provider)
                  (.build-index
                   (lambda (rows columns)
                     (set! events (cons (list 'build columns) events))
                     ((.ref gerbil-ascent-hash-index-provider '.build-index)
                      rows columns)))
                  (.lookup-index
                   (lambda (index key)
                     (set! events (cons (list 'lookup key) events))
                     ((.ref gerbil-ascent-hash-index-provider '.lookup-index)
                      index key)))))
             (x (gerbil-ascent-variable 'x))
             (z (gerbil-ascent-variable 'z))
             (expression
              (gerbil-ascent-expression '(x)
                (lambda (value)
                  (set! events (cons 'expression events)) (+ value 1))))
             (program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'seed 1 '((2)))
                     (gerbil-ascent-relation 'probe 4
                       (map (lambda (n) (list 7 n (+ n 1) (* n 2))) (iota 40))
                       provider)
                     (gerbil-ascent-relation 'out 1 []))
               (list (gerbil-ascent-rule
                      (list (gerbil-ascent-atom 'out (list z)))
                      (list (gerbil-ascent-atom 'seed (list x))
                            (gerbil-ascent-guard '(x) (lambda (_x) #t))
                            (gerbil-ascent-atom 'probe
                              (list (gerbil-ascent-literal 7) x expression z)))))
               64 64 128))
             (relations (.ref program 'relations))
             (analysis
              (gerbil-ascent-prepare-program relations (.ref program 'rules)
                (gerbil-ascent-program-schema program relations) #f))
             (body (vector-ref (car (vector-ref analysis 2)) 1))
             (atom (vector-ref (caddr body) 1)))
        (check-equal? events [])
        (check-equal? (vector-ref atom 2) '(0 1 2))
        (check-equal? (vector-ref atom 4)
                      (map (cut list-ref (vector-ref atom 1) <>) '(0 1 2)))
        (let* ((old (ascent-index-reference-evaluate-program program))
               (trace (reverse events)))
          (set! events [])
          (let (new (gerbil-ascent-evaluate-program program))
            (check-equal? ((.ref new 'rows-of) 'out) '((4)))
            (check-equal? ((.ref new 'rows-of) 'out) ((.ref old 'rows-of) 'out))
            (check-equal? (reverse events) trace)
            (check-equal? (car trace) '(build (0 1 2)))
            (check-equal? (cadr trace) 'expression)
            (check-equal? (if (member '(lookup (7 2 3)) trace) #t #f) #t)))))
    (test-case "prepared keys preserve false values and missing-variable errors"
      (let (terms
            (list '(literal . 7) '(variable . x)
                  (cons 'expression (vector '(x) identity))))
        (check-equal? (gerbil-ascent-index-key/terms terms '((x . #f))) '(7 #f #f))
        (check-equal? (gerbil-ascent-index-key/terms [] []) [])
        (check-exception (gerbil-ascent-index-key/terms terms []) true)))
    (test-case "bound-column index preserves two-hop join semantics"
      (let* ((program (ascent-index-fixture-program))
             (rows ((.ref (gerbil-ascent-evaluate-program program) 'rows-of)
                    'two-hop)))
        (check-equal? (length rows) 49)
        (check-equal? (not (not (member '(0 2) rows))) #t)
        (check-equal? (not (not (member '(48 50) rows))) #t)
        (check-equal? (member '(0 3) rows) #f)))
    (test-case "a custom alist Provider replaces the physical index"
      (let* ((builds 0)
             (provider
              (ascent-index-alist-provider
               (lambda (_columns) (set! builds (+ builds 1)))))
             (rows
              ((.ref (gerbil-ascent-evaluate-program
                      (ascent-index-fixture-program 50 provider))
                     'rows-of)
               'two-hop)))
        (check-equal? (> builds 0) #t)
        (check-equal? (length rows) 49)
        (check-equal? (not (not (member '(48 50) rows))) #t)))
    (test-case "composite group and node index preserves two-hop joins"
      (let* ((built-columns [])
             (provider
              (ascent-index-alist-provider
               (lambda (columns)
                 (set! built-columns (cons columns built-columns)))))
             (rows
              ((.ref (gerbil-ascent-evaluate-program
                      (ascent-composite-index-fixture-program 50 provider))
                     'rows-of)
               'two-hop)))
        (check-equal? (not (not (member '(0 1) built-columns))) #t)
        (check-equal? (length rows) 98)
        (check-equal? (not (not (member '(0 0 2) rows))) #t)
        (check-equal? (not (not (member '(1 148 150) rows))) #t)
        (check-equal? (member '(0 100 102) rows) #f)))
    (test-case "source append extends an existing index without rebuilding"
      (let* ((builds 0)
             (provider
              (ascent-index-alist-provider
               (lambda (_columns) (set! builds (+ builds 1)))))
             (session
              (gerbil-ascent-open-session
               (ascent-index-fixture-program 50 provider))))
        (check-equal? (length ((.ref (gerbil-ascent-session-run session)
                                  'rows-of) 'two-hop)) 49)
        (check-equal? (> builds 0) #t)
        (let (before builds)
          (let append ((from 50))
            (when (< from 60)
              (gerbil-ascent-session-append-source!
               session 'edge (list from (+ from 1)))
              (let (rows ((.ref (gerbil-ascent-session-run session) 'rows-of)
                          'two-hop))
                (check-equal? (length rows) from)
                (check-equal?
                 (not (not (member (list (- from 1) (+ from 1)) rows)))
                 #t)
                (check-equal? builds before))
              (append (+ from 1)))))))
    (test-case "bound composite key reads a merged lattice through its index"
      (let* ((built-columns [])
             (provider
              (ascent-index-alist-provider
               (lambda (columns)
                 (set! built-columns (cons columns built-columns)))))
             (rows
              ((.ref (gerbil-ascent-evaluate-program
                      (ascent-lattice-index-fixture-program 50 provider))
                     'rows-of)
               'found)))
        (check-equal? (not (not (member '(0 1) built-columns))) #t)
        (check-equal? (length rows) 50)
        (for-each
         (lambda (node)
           (check-equal?
            (not (not (member (list (modulo node 2) node (+ node 1))
                              rows)))
            #t))
         (iota 50))))
    (test-case "lattice refinement removes obsolete indexed relation rows"
      (for-each
       (lambda (provider)
         (let* ((program
                 (.o (:: @ (ascent-lattice-index-fixture-program
                            50 provider))
                     max-input-facts: 151
                     max-derived-facts: 102
                     max-output-facts: 255))
                (session (gerbil-ascent-open-session program))
                (first (gerbil-ascent-session-run session)))
           (check-equal? (length ((.ref first 'rows-of) 'found)) 50)
           (gerbil-ascent-session-append-source!
            session 'candidate '(0 0 0))
           (let (rows ((.ref (gerbil-ascent-session-run session) 'rows-of)
                       'found))
             (check-equal? (length rows) 50)
             (check-equal? (not (not (member '(0 0 0) rows))) #t)
             (check-equal? (member '(0 0 1) rows) #f)
             (check-equal? (length ((.ref first 'rows-of) 'found)) 50))))
       (list #f (ascent-index-alist-provider))))
    (test-case "malformed Provider values fail at the boundary"
      (check-exception
       (gerbil-ascent-relation
        'invalid 2 []
        (.o (:: @ gerbil-ascent-hash-index-provider)
            (.build-index #f)))
       true)
      (check-exception
       (gerbil-ascent-evaluate-program
        (ascent-index-fixture-program
         50 (.o (:: @ gerbil-ascent-hash-index-provider)
                (.build-index (lambda (_rows _columns) 'broken))
                (.lookup-index (lambda (_index _key) 'broken)))))
       true))))
