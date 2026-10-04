;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite test-case check-equal?)
        (only-in :gerbil-ascent/program/positive gerbil-ascent-index-key/terms)
        (only-in :gerbil-ascent/program/funs gerbil-ascent-expression-value)
        (only-in :gerbil-ascent/t/performance/native-library assert-native-library!))
(export ascent-prepared-key-performance-test)

;;; Frozen general key implementation from 0ac40f8. Both implementations are
;;; natively compiled. Preparation, index construction and whole solves are
;;; excluded; callback order has a separate evaluator qualification Case.
(def (reference-key terms columns environment)
  (map (lambda (column)
         (let (term (list-ref terms column))
           (case (car term)
             ((literal) (cdr term))
             ((expression) (gerbil-ascent-expression-value (cdr term) environment))
             (else
              (let (bound (assq (cdr term) environment))
                (unless bound (error "unbound ASCENT index variable" (cdr term)))
                (cdr bound))))))
       columns))

(def (sample call expected)
  (let ((start (current-jiffy)) (last #f))
    (let loop ((n 32))
      (unless (zero? n)
        (set! last (call))
        (loop (- n 1))))
    (let (elapsed (- (current-jiffy) start))
      (check-equal? last expected)
      elapsed)))

(def (compare label width columns target?)
  (let* ((terms (map (lambda (n)
                       (if (even? n) (cons 'literal n) '(variable . x)))
                     (iota width)))
         (selected (map (cut list-ref terms <>) columns))
         (environment '((x . #f)))
         (old-call (lambda () (reference-key terms columns environment)))
         (new-call (lambda () (gerbil-ascent-index-key/terms selected environment)))
         (expected (map (lambda (n) (if (even? n) n #f)) columns))
         (old []) (new []) (wins 0))
    (sample old-call expected)
    (sample new-call expected)
    (let loop ((n 0))
      (when (< n 1000)
        (when (zero? (modulo n 20)) (##gc))
        (let-values (((a b)
                      (if (even? n)
                        (let* ((a (sample old-call expected))
                               (b (sample new-call expected))) (values a b))
                        (let* ((b (sample new-call expected))
                               (a (sample old-call expected))) (values a b)))))
          (set! old (cons a old))
          (set! new (cons b new))
          (when (< b a) (set! wins (+ wins 1))))
        (loop (+ n 1))))
    (let ((a (list-ref (list-sort < old) 500))
          (b (list-ref (list-sort < new) 500)))
      (displayln "PREPARED-KEY " label " pairs=1000 batch=32 wins=" wins
                 " reference-median-jiffies=" a " candidate-median-jiffies=" b)
      (force-output)
      (and (<= b a) (or (not target?) (>= wins 900))))))

(def ascent-prepared-key-performance-test
  (test-suite "Prepared general index key selection"
    (test-case "wide targets qualify and the narrow control does not regress"
      (assert-native-library!)
      (let (qualified? #t)
        (for-each
         (lambda (entry)
           (unless (apply compare entry) (set! qualified? #f)))
         (list (list 'narrow-control 2 '(0 1) #f)
               (list 'sparse-64 64 '(62 63) #t)
               (list 'sparse-128 128 '(126 127) #t)
               (list 'composite-64 64 (iota 64) #t)))
        (unless qualified?
          (error "prepared key selection failed paired admission"))))))
