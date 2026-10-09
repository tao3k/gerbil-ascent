;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
 (only-in :gerbil-ascent/table/funs gerbil-ascent-index-row-snapshot/arity)
 :gerbil-ascent/t/performance/provider-packet/fixture)
(export ascent-provider-packet-test)
(def ascent-provider-packet-test
 (test-suite "Provider packet admission"
  (test-case "all widths preserve field identity with detached spines"
   (for-each (lambda (width)
    (let* ((value (vector 'borrowed)) (row (make-list width value))
           (rows (list row row)) (copy (gerbil-ascent-index-row-snapshot/arity rows width)))
     (check-equal? copy rows)
     (check-equal? (eq? copy rows) #f)
     (when (positive? width)
      (check-equal? (eq? (car copy) row) #f)
      (check-equal? (eq? (car copy) (cadr copy)) #f)
      (check-equal? (andmap (cut eq? <> value) (car copy)) #t)
      (set-car! row 'mutated)
      (check-equal? (eq? (caar copy) value) #t)
      (set-car! (car copy) 'private)
      (check-equal? (eq? (caadr copy) value) #t))))
    (iota 257)))
  (test-case "bounded rejection of short long improper and cyclic rows"
   (for-each (lambda (width)
    (let (cycle (list 'cycle))
     (set-cdr! cycle cycle)
     (for-each (lambda (bad)
      (check-equal?
       (with-catch (lambda (failure) (error-message failure))
        (lambda () (gerbil-ascent-index-row-snapshot/arity
                     (list (make-list width #f) bad) width) 'unexpected))
       "ASCENT index provider returned wrong row arity"))
      (append (list cycle (make-list (+ width 1) #f) 'atom)
       (if (zero? width) [] (list (make-list (- width 1) #f) (cons #f 'improper)))))))
    (iota 257)))
  (test-case "complete warm lookup agrees with frozen owner and independent checksum"
   (for-each (lambda (width)
    (for-each (lambda (count)
     (let (input (packet-input width count 3))
      (check-equal? (packet-workflow #t input) (packet-expected input))
      (check-equal? (packet-workflow #f input) (packet-expected input)))) '(0 1 31 32 33 64)))
    '(2 3 4 8 64 256)))))
