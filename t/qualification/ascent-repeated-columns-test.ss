;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/list/list append-map) :std/test :gerbil-ascent/table/funs
 (prefix-in :gerbil-ascent/t/performance/repeated-columns/reference old-))
(export ascent-repeated-columns-test)
(def (column-tuples width)
 (if (= width 0) (list [])
  (append-map (lambda (tail) (map (lambda (column) (cons column tail)) '(0 1 2)))
              (column-tuples (- width 1)))))
(def ascent-repeated-columns-test
 (test-suite "Repeated-column projection and index lifetime"
  (test-case "all 121 small column sequences retain values and bucket order"
   (let* ((field (vector 'shared)) (rows (list (list #f field 2) (list #f field 3) (list #t field 2)))
          (batch (reverse rows)))
    (for-each (lambda (width)
     (for-each (lambda (columns)
      (let ((a (old-gerbil-ascent-index-build rows columns)) (b (gerbil-ascent-index-build rows columns)))
       (old-gerbil-ascent-index-extend! a batch columns)
       (gerbil-ascent-index-extend! b batch columns)
       (for-each (lambda (row)
        (let (key (gerbil-ascent-index-key row columns))
         (check-equal? key (map (lambda (column) (list-ref row column)) columns))
         (check-equal? key (old-gerbil-ascent-index-key row columns))
         (check-equal? (hash-get b key) (hash-get a key)))) rows))) (column-tuples width))) (iota 5))))
  (test-case "field identities metadata changes and integral inexact columns remain observable"
   (let* ((field (vector 'shared)) (row (list #f field 7)) (columns (list 0 0 2)))
    (check-equal? (gerbil-ascent-index-key row columns) '(#f #f 7))
    (set-car! (cdr columns) 1)
    (let (key (gerbil-ascent-index-key row columns))
     (check-equal? (eq? (cadr key) field) #t)
     (check-equal? key (old-gerbil-ascent-index-key row columns)))
    (check-equal? (gerbil-ascent-index-key row '(0.0 2.0))
                  (old-gerbil-ascent-index-key row '(0.0 2.0)))))
  (test-case "repeated-column extension leaves held bucket spines intact"
   (let* ((rows '((#f first) (#f second))) (index (gerbil-ascent-index-build rows '(0 0)))
          (held (hash-get index '(#f #f))) (incoming '(#f third)))
    (gerbil-ascent-index-extend! index (list incoming) '(0 0))
    (check-equal? held rows)
    (check-equal? (hash-get index '(#f #f)) (cons incoming rows))
    (check-equal? (eq? (cdr (hash-get index '(#f #f))) held) #t)))))
