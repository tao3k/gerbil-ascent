;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite test-case check-equal?)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/scheme-checked
                 relational-compute relational-operator-literal)
        (only-in :gerbil-ascent/t/performance/native-library assert-native-library!))
(export ascent-checked-call-performance-test)

;;; Frozen calling convention from a97762d, compiled with the same native
;;; toolchain as the candidate. This isolates calls, excluding declaration
;;; construction, admission, environment lookup and complete solve costs.
(def (reference-call operation-procedure operands)
  (lambda values
    (let loop ((remaining operands) (bound values) (arguments []))
      (if (null? remaining)
        (begin
          (unless (null? bound)
            (error "relational operator argument mismatch"))
          (apply operation-procedure (reverse arguments)))
        (let (operand (car remaining))
          (if (eq? (vector-ref operand 0) 'variable)
            (if (pair? bound)
              (loop (cdr remaining) (cdr bound)
                    (cons (car bound) arguments))
              (error "relational operator argument mismatch"))
            (loop (cdr remaining) bound
                  (cons (vector-ref operand 1) arguments))))))))

(def (checked-plus left right)
  (unless (and (exact-integer? left) (exact-integer? right))
    (error "+ expects exact integers" left right))
  (+ left right))

(def (sample call inputs expected)
  (let ((start (current-jiffy)) (last #f))
    (let loop ((n 256))
      (unless (zero? n)
        (set! last (apply call inputs))
        (loop (- n 1))))
    (let (elapsed (- (current-jiffy) start))
      (check-equal? last expected)
      elapsed)))

(def (compare label operation operands inputs expected)
  (let* ((clause (relational-compute 'out operation operands))
         (candidate (.ref clause 'compute))
         (reference
          (reference-call (if (eq? operation '+) checked-plus identity)
                          (vector-ref (.ref clause 'checked-operator) 2)))
         (old []) (new []) (wins 0))
    (sample reference inputs expected)
    (sample candidate inputs expected)
    (let loop ((n 0))
      (when (< n 1000)
        (when (zero? (modulo n 20)) (##gc))
        (let-values (((a b)
                      (if (even? n)
                        (let* ((a (sample reference inputs expected))
                               (b (sample candidate inputs expected))) (values a b))
                        (let* ((b (sample candidate inputs expected))
                               (a (sample reference inputs expected))) (values a b)))))
          (set! old (cons a old))
          (set! new (cons b new))
          (when (< b a) (set! wins (+ wins 1))))
        (loop (+ n 1))))
    (let ((a (list-ref (list-sort < old) 500))
          (b (list-ref (list-sort < new) 500)))
      (displayln "CHECKED-CALL " label " pairs=1000 batch=256 wins=" wins
                 " reference-median-jiffies=" a " candidate-median-jiffies=" b)
      (force-output)
      (and (>= wins 900) (<= b a)))))

(def ascent-checked-call-performance-test
  (test-suite "Checked scalar call specialization"
    (test-case "all six calling conventions qualify 1000 alternating pairs"
      (assert-native-library!)
      (let ((two (relational-operator-literal 2))
            (three (relational-operator-literal 3))
            (qualified? #t))
        (for-each
         (lambda (entry)
           (unless (apply compare entry) (set! qualified? #f)))
         (list (list 'binary-variables '+ '(x y) '(2 3) 5)
               (list 'binary-right-literal '+ (list 'x three) '(2) 5)
               (list 'binary-left-literal '+ (list two 'y) '(3) 5)
               (list 'binary-literals '+ (list two three) [] 5)
               (list 'unary-variable 'identity '(x) '(#f) #f)
               (list 'unary-literal 'identity
                     (list (relational-operator-literal #f)) [] #f)))
        (unless qualified?
          (error "checked call specialization failed paired admission"))))))
