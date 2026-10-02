;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite)
        (only-in :std/list/list append-map)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :gerbil-ascent/program/funs gerbil-ascent-bind-row)
        (only-in :gerbil-ascent/t/qualification/ascent-binding-reference-fixture
                 ascent-reference-bind-row ascent-binding-atom-plan))
(export ascent-binding-test)

(def (tuples alphabet width)
  (if (= width 0)
    [[]]
    (let (tails (tuples alphabet (- width 1)))
      (append-map (lambda (head)
                    (map (lambda (tail) (cons head tail)) tails))
                  alphabet))))

(def +environments+
  '(() ((x . 0)) ((x . 1)) ((y . 0)) ((y . 1))
    ((x . 0) (y . 0)) ((x . 0) (y . 1))
    ((x . 1) (y . 0)) ((x . 1) (y . 1))))

(def (prepared terms environment)
  (vector-ref (ascent-binding-atom-plan terms (map car environment)) 3))

(def (finite-bindings width)
  (let ((snapshots 0)
        (rows (tuples '(0 1) width)))
    (for-each
     (lambda (terms)
       (for-each
        (lambda (environment)
          (let (bindings (prepared terms environment))
            (for-each
             (lambda (row)
               (let ((old (ascent-reference-bind-row terms row environment))
                     (new (gerbil-ascent-bind-row bindings row environment)))
                 (unless (equal? old new)
                   (error "prepared bindings changed row matching"
                          terms row environment old new))
                 (set! snapshots (+ snapshots 1))))
             rows)))
        +environments+))
     (tuples '((variable . x) (variable . y)
               (literal . 0) (literal . 1) (wildcard . #f)) width))
    (check-equal? snapshots (* 9 (expt 10 width)))
    (displayln "BINDING-PARITY width=" width " snapshots=" snapshots)))

(def (outcome call)
  (with-catch (lambda (failure) (list 'error (error-message failure))) call))

(def (check-binding terms rows environment)
  (let (bindings (prepared terms environment))
    (for-each
     (lambda (row)
       (check-equal?
        (outcome (lambda () (gerbil-ascent-bind-row bindings row environment)))
        (outcome (lambda () (ascent-reference-bind-row terms row environment)))))
     rows)))

(def ascent-binding-test
  (test-suite "ASCENT checked row binding specialization"
    (poo-flow-test-case "nullary terms retain existing environments"
      (finite-bindings 0))
    (poo-flow-test-case "all unary terms preserve bindings and rejection"
      (finite-bindings 1))
    (poo-flow-test-case "all binary terms preserve binding order and repeats"
      (finite-bindings 2))
    (poo-flow-test-case "all ternary terms preserve binding order and repeats"
      (finite-bindings 3))
    (poo-flow-test-case "all four-column terms preserve binding order and repeats"
      (finite-bindings 4))
    (poo-flow-test-case "pattern outputs stay bound for later variable comparisons"
      (check-binding
       (list (cons 'pattern (vector '(x) (lambda (value) (list value))))
             (cons 'variable 'x) (cons 'variable 'y))
       '((0 0 1) (0 1 1) (1 1 0)) []))
    (poo-flow-test-case "row-local expression inputs retain evaluation order"
      (check-binding
       (list (cons 'variable 'x)
             (cons 'expression (vector '(x) (lambda (x) (+ x 1))))
             (cons 'variable 'y) (cons 'variable 'y))
       '((2 3 0 0) (2 4 0 0) (2 3 0 1)) []))
    (poo-flow-test-case "external bindings still reject mismatches"
      (check-binding
       (list (cons 'variable 'x)
             (cons 'expression (vector '(x) (lambda (x) (+ x 1))))
             (cons 'variable 'y))
       '((2 3 0) (1 2 0)) '((x . 2))))
    (poo-flow-test-case "false values are bindings rather than missing names"
      (check-binding
       '((variable . x) (variable . x) (variable . y) (variable . y))
       '((#f #f #t #t) (#f #t #t #t)) [])
      (check-binding
       (list (cons 'pattern (vector '(x) (lambda (_) '(#f))))
             (cons 'variable 'x)
             (cons 'expression (vector '(x) not)))
       '((0 #f #t) (0 #t #t)) []))
    (poo-flow-test-case "failed and malformed patterns preserve outcomes"
      (for-each
       (lambda (matcher)
         (check-binding
          (list (cons 'pattern (vector '(x) matcher)) (cons 'variable 'y))
          '((0 1)) []))
       (list (lambda (_) #f) (lambda (_) 0) (lambda (_) '(0 1)))))
    (poo-flow-test-case "admission still rejects duplicate pattern bindings"
      (check-equal?
       (outcome
        (lambda ()
          (prepared (list (cons 'variable 'x)
                          (cons 'pattern (vector '(x) (lambda (x) (list x))))) [])))
       '(error "ASCENT pattern variable already bound")))))
