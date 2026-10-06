;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :clan/poo/object .o)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        :gerbil-ascent/table/access
        (only-in :gerbil-ascent/table/funs gerbil-ascent-index-build gerbil-ascent-index-extend!)
        :gerbil-ascent/t/performance/index-build/fixture)
(export ascent-index-build-test)
(def ascent-index-build-test
  (test-suite "Owned physical index construction"
    (test-case "all ordered repeated and arbitrary columns preserve finite row order"
      (for-each
       (lambda (size)
         (let* ((source (take '((#f (a)) (0 (b)) (#f (a)) (0 (a))) size))
                (batch '((#f (a)) (1 (c)))))
           (for-each
            (lambda (columns)
              (let* ((index (gerbil-ascent-index-build source columns))
                     (keys (map (lambda (row) (index-build-key row columns)) (append source batch)))
                     (oracle (lambda (rows key) (filter (lambda (row) (equal? (index-build-key row columns) key)) rows))))
                (for-each (lambda (key) (check-equal? (or (hash-get index key) []) (oracle source key))) keys)
                (gerbil-ascent-index-extend! index batch columns)
                (for-each (lambda (key) (check-equal? (or (hash-get index key) []) (oracle (append (reverse batch) source) key))) keys)))
            '(() (0) (1) (0 1) (1 0) (0 0) (1 1))))) (iota 5)))
    (test-case "scalar and composite builds share row identities but own bucket headers"
      (for-each
       (lambda (columns)
         (let* ((row (list #f 'value)) (source (list row row))
                (key (index-build-key row columns))
                (index (gerbil-ascent-physical-index-build gerbil-ascent-hash-index-provider source columns))
                (bucket (gerbil-ascent-physical-index-rows gerbil-ascent-hash-index-provider index key)))
           (check-equal? (eq? (car bucket) row) #t)
           (check-equal? (eq? (cadr bucket) row) #t)
           (check-equal? (eq? bucket source) #f)
           (gerbil-ascent-physical-index-extend! gerbil-ascent-hash-index-provider index (list row) columns)
           (check-equal? (length bucket) 2)
           (set-car! bucket '(changed))
           (check-equal? source (list row row)))) '((0) (0 1))))
    (test-case "wide batch projections retain boundaries order and fresh column selection"
      (let* ((rows (map (lambda (n) (map (lambda (column) (list n column)) (iota 64))) (iota 4)))
             (batch (list (car rows) (cadr rows))))
        (for-each
         (lambda (columns)
           (let* ((index (gerbil-ascent-index-build rows columns))
                  (key-of (lambda (row) (index-build-key row columns))))
             (gerbil-ascent-index-extend! index batch columns)
             (for-each
              (lambda (row)
                (let (key (key-of row))
                  (check-equal? (hash-ref index key)
                    (filter (lambda (candidate) (equal? key (key-of candidate)))
                            (append (reverse batch) rows))))) rows)))
         '(() (0) (63) (0 8 56 63) (0 1 2 3) (63 0 63) (2 2)))
        (let* ((columns (list 0 8)) (index (gerbil-ascent-index-build rows columns)))
          (set-car! (cdr columns) 56)
          (gerbil-ascent-index-extend! index batch columns)
          (check-equal? (hash-ref index (index-build-key (car rows) columns)) (list (car rows))))))
    (test-case "custom provider borrows rows and receives equal isolated column and key headers"
      (let* ((events []) (source '((1) (2))) (batch '((3))) (columns (list 0)) (key (list 1))
             (provider (.o (:: @ gerbil-ascent-hash-index-provider)
                         (.build-index (lambda (rows cols) (set! events (cons (list 'build (eq? rows source) (eq? cols columns) (equal? cols columns)) events)) 'opaque))
                         (.extend-index! (lambda (index rows cols) (set! events (cons (list 'extend index (eq? rows batch) (eq? cols columns) (equal? cols columns)) events)) index))
                         (.lookup-index (lambda (index selected) (set! events (cons (list 'lookup index (eq? selected key) (equal? selected key)) events)) source)))))
        (let (index (gerbil-ascent-physical-index-build provider source columns))
          (gerbil-ascent-physical-index-extend! provider index batch columns)
          (check-equal? (gerbil-ascent-physical-index-rows provider index key) source)
          (check-equal? (reverse events) '((build #t #f #t) (extend opaque #t #f #t) (lookup opaque #f #t))))))
    (test-case "dense unique empty and small native lifecycles match frozen baseline"
      (for-each
       (lambda (size)
         (for-each (lambda (columns)
                     (let* ((source (index-build-source size)) (batch (index-build-source 8 size))
                            (keys (map (lambda (row) (index-build-key row columns)) (append source batch))))
                       (check-equal? (index-build-lifecycle #f source batch columns keys)
                                     (index-build-lifecycle #t source batch columns keys))))
                   '((0) (1) (0 2) (1 3)))) '(0 1 4 64)))
    (test-case "complete compiled self joins match frozen evaluator and independent rows"
      (let (program (index-build-program))
        (check-equal? (index-build-solve #f program) (map list (iota 1024)))
        (check-equal? (index-build-solve #f program) (index-build-solve #t program))))))
