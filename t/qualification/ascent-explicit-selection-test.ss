;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/core/relation-view
 :gerbil-ascent/t/performance/explicit-selection/fixture)
(export ascent-explicit-selection-test)
(def (check-selection rows columns key)
 (let* ((input (vector rows columns key)) (old (selection-workflow #t input)) (new (selection-workflow #f input)))
  (check-equal? new old)
  (check-equal? new (selection-expected input))))
(def (column-sequences n)
 (if (zero? n) '(())
  (apply append (map (lambda (tail) (map (lambda (head) (cons head tail)) '(0 1 2))) (column-sequences (- n 1))))))
(def ascent-explicit-selection-test
 (test-suite "Ordered explicit row selection"
  (test-case "all small column orders preserve exact matching and output order"
   (let (rows '((0 1 2) (0 1 3) (4 1 2)))
    (for-each (lambda (n)
     (for-each (lambda (columns)
      (let (key (map (lambda (column) (vector-ref '#(0 1 2) column)) columns))
       (check-selection rows columns key)
       (unless (null? key)
        (check-selection rows columns (append (drop-right key 1) '(-1)))))) (column-sequences n))) (iota 4))))
  (test-case "duplicates and nested field values retain equality semantics"
   (check-selection '((a (x 1) #f) (b (x 1) #t) (c (x 2) #f)) '(1 1 2) '((x 1) (x 1) #f))
   (check-selection '((a 1) (b 1)) '(1 1) '(1 2)))
  (test-case "selection consumes independent tails during reentrant traversal"
   (let* ((rows '((1 20 30) (2 20 40))) (view (gerbil-ascent-explicit-view rows 2)) (seen []) (inner []))
    (gerbil-ascent-for-each-row
     (lambda (row)
      (set! seen (cons (car row) seen))
      (gerbil-ascent-for-each-row
       (lambda (nested) (set! inner (cons (car nested) inner)) (set-car! nested -1))
       (gerbil-ascent-view-select view '(1) '(20)))
      (set-car! row -2))
     (gerbil-ascent-view-select view '(1 2) '(20 30)))
    (check-equal? seen '(1))
    (check-equal? (reverse inner) '(1 2))
    (check-equal? (gerbil-ascent-view-rows view) rows)
    (check-equal? (gerbil-ascent-view-contains? view '(1 20 30)) #t)))
  (test-case "invalid selectors retain delayed errors and short-circuiting"
   (def (outcome old? rows columns key)
    (with-catch (lambda (_) 'rejected) (lambda () (selection-workflow old? (vector rows columns key)))))
   (for-each (lambda (query)
    (check-equal? (outcome #f '((1 2)) (car query) (cadr query))
                  (outcome #t '((1 2)) (car query) (cadr query))))
    '(((0 10) (0 0)) ((0 10) (1 0)) ((-1) (1)) ((a) (1)) ((0 1) (1)) ((0) (1 2))))
   (check-equal? (outcome #f '((1 2)) '(0 10) '(0 0)) [])
   (check-equal? (outcome #f '((1 2)) '(0 10) '(1 0)) 'rejected)
   (check-equal? (outcome #f [] '(a) '(1)) []))
  (test-case "lazy count does not force rows and each query prepares fresh selectors"
   (let* ((forced 0) (columns '(1 2)) (key (list 20 30))
          (view (gerbil-ascent-lazy-explicit-view (delay (begin (set! forced (+ forced 1)) '((1 20 30) (2 20 40)))) 2)) (seen []))
    (check-equal? (relation-view-count view) 2)
    (check-equal? forced 0)
    (def (visit)
     (set! seen [])
     (gerbil-ascent-for-each-row (lambda (row) (set! seen (cons (car row) seen)))
      (gerbil-ascent-view-select view columns key)))
    (visit) (check-equal? seen '(1)) (check-equal? forced 1)
    (set-car! (cdr key) 40)
    (visit) (check-equal? seen '(2)) (check-equal? forced 1)
    (check-equal? (relation-view-count view) 2)))))
