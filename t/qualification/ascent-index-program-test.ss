;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :clan/poo/object .o .ref)
        (only-in :core/observability/testing-case
                 poo-flow-test-case)
        (only-in :gerbil-ascent/t/qualification/ascent-index-program-fixture
                 ascent-index-fixture-program
                 ascent-composite-index-fixture-program
                 ascent-lattice-index-fixture-program
                 ascent-index-alist-provider)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program gerbil-ascent-relation
                 gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-run))

(export ascent-index-program-test)

(def ascent-index-program-test
  (test-suite "ASCENT indexed relation access"
    (poo-flow-test-case "bound-column index preserves two-hop join semantics"
      (let* ((program (ascent-index-fixture-program))
             (rows ((.ref (gerbil-ascent-evaluate-program program) 'rows-of)
                    'two-hop)))
        (check-equal? (length rows) 49)
        (check-equal? (not (not (member '(0 2) rows))) #t)
        (check-equal? (not (not (member '(48 50) rows))) #t)
        (check-equal? (member '(0 3) rows) #f)))
    (poo-flow-test-case "a custom alist Provider replaces the physical index"
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
    (poo-flow-test-case "composite group and node index preserves two-hop joins"
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
    (poo-flow-test-case "source append extends an existing index without rebuilding"
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
    (poo-flow-test-case "bound composite key reads a merged lattice through its index"
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
    (poo-flow-test-case "lattice refinement removes obsolete indexed relation rows"
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
    (poo-flow-test-case "malformed Provider values fail at the boundary"
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
