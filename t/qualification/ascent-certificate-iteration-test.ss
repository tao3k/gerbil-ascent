;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
 (only-in :gerbil-ascent/candidate/certificate-limits certificate-for-each-while)
 (only-in :gerbil-ascent/program/finite-arithmetic relational-capped-power))
(export ascent-certificate-iteration-test)
(def (reference-visit proceed? visit items)
 (cond ((not (proceed?)) #f) ((null? items) #t)
       (else (visit (car items)) (reference-visit proceed? visit (cdr items)))))
(def (observe-visit run length stop-at)
 (let ((seen 0) (trace '()))
  (let (result (run (lambda () (set! trace (cons (list 'check seen) trace)) (< seen stop-at))
                   (lambda (item) (set! trace (cons (list 'visit item) trace)) (set! seen (+ seen 1)))
                   (iota length)))
   (list result (reverse trace)))))
(def ascent-certificate-iteration-test
 (test-suite "Bounded arithmetic and exact material traversal controls"
  (test-case "stop checks and visits retain the complete original event trace"
   (for-each (lambda (length)
    (for-each (lambda (stop-at)
     (check-equal? (observe-visit certificate-for-each-while length stop-at)
                   (observe-visit reference-visit length stop-at))) (iota 8))) (iota 8)))
  (test-case "truthy guard results still produce a boolean result"
   (check-equal? (certificate-for-each-while (lambda () 'ready) void '(a b)) #t)
   (check-equal? (certificate-for-each-while (lambda () #f) void '()) #f))
  (test-case "truncated power matches independent exact arithmetic over finite grids"
   (for-each (lambda (cap)
    (for-each (lambda (base)
     (for-each (lambda (exponent)
      (check-equal? (relational-capped-power cap base exponent) (min cap (expt base exponent))))
      (iota 12))) (iota 12))) (iota 24)))
  (test-case "astronomical exponents saturate before recursive descent"
   (let (huge (arithmetic-shift 1 16384))
    (check-equal? (relational-capped-power 100 2 huge) 100)
    (check-equal? (relational-capped-power 0 2 huge) 0)
    (check-equal? (relational-capped-power 100 0 huge) 0)
    (check-equal? (relational-capped-power 100 1 huge) 1)))))
