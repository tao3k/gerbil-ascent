;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test (only-in :clan/poo/object .o)
 :gerbil-ascent/temporal/lens
 :gerbil-ascent/t/performance/temporal-contract/fixture
 (prefix-in :gerbil-ascent/t/performance/temporal-contract/reference old-))
(export ascent-temporal-contract-test)
(def (outcome call)
 (with-catch (lambda (failure) (error-message failure)) call))
(def ascent-temporal-contract-test
 (test-suite "Temporal value contract and construction"
  (test-case "complete constructors agree with frozen owner and canonical coordinates"
   (for-each (lambda (count)
    (let (input (temporal-input count (if (zero? count) 0 (min 512 (* count 2))) 2))
     (check-equal? (temporal-workflow #f input) (temporal-expected input))
     (check-equal? (temporal-workflow #t input) (temporal-expected input)))) '(0 2 4 8 32 64 128 256)))
  (test-case "duplicate symbols and structural parent rows retain diagnostics"
   (for-each (lambda (ids)
    (check-equal? (outcome (lambda () (temporal-lens 0 'clock 0 10 0 'cut ids 0 #f)))
                  (outcome (lambda () (old-temporal-lens 0 'clock 0 10 0 'cut ids 0 #f)))))
    '((a a) (a b a) (a b b) (a b c a)))
   (for-each (lambda (parents)
    (check-equal? (outcome (lambda () (temporal-source 'source 0 'clock '((a 0 0) (b 1 0)) parents)))
                  (outcome (lambda () (old-temporal-source 'source 0 'clock '((a 0 0) (b 1 0)) parents)))))
    '(((a b) (a b)) ((a b) (b a) (a b)) ((a a) (a a)))))
  (test-case "constructor interval callback schedule remains two ordered passes"
   (def (trace old?)
    (let* ((calls []) (bound (.o kind: 'ascent.temporal-interval.v1
       projection: (lambda () (set! calls (cons 'bound calls)) '(between 0 1)))))
     (let (result ((if old? old-temporal-source temporal-source) 'source 0 'clock
                    (list (list 'a bound 0) (list 'b bound 0)) []))
      (list (temporal-projection result) calls))))
   (check-equal? (trace #f) (trace #t)))
  (test-case "mutating caller spines and projections cannot change captured coordinates"
   (let* ((members (list 'b 'a)) (events (list (list 'a 0 0) (list 'b 1 0)))
          (parents (list (list 'a 'b)))
          (lens (temporal-lens 0 'clock 0 10 1 'cut members 1 #t))
          (source (temporal-source 'source 0 'clock events parents))
          (expected (temporal-projection source)) (projection (temporal-projection source)))
    (set-car! members 'changed) (set-car! (car events) 'changed)
    (set-car! (car parents) 'changed) (set-car! projection 'changed)
    (check-equal? (temporal-projection source) expected)
    (check-equal? (list-ref (temporal-projection lens) 6) '(a b))))))
