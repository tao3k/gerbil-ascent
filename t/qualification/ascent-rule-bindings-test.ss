;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        :gerbil-ascent/program/objects
        :gerbil-ascent/core/rule-bindings
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (rename-in (only-in :gerbil-ascent/t/performance/rule-bindings/reference
                           gerbil-ascent-bind-row gerbil-ascent-expression-value)
                   (gerbil-ascent-bind-row old-bind) (gerbil-ascent-expression-value old-expression))
        (rename-in (only-in :gerbil-ascent/t/performance/rule-bindings/reference-evaluate
                           gerbil-ascent-evaluate-program)
                   (gerbil-ascent-evaluate-program old-evaluate))
        :gerbil-ascent/t/performance/rule-bindings/fixture)
(export ascent-rule-bindings-test)
(def (outcome call)
  (with-catch (lambda (failure) (list 'error (error-message failure) (error-irritants failure))) call))
(def ascent-rule-bindings-test
  (test-suite "Runtime rule bindings and callback ownership"
    (test-case "all callback arities preserve values and first missing name"
      (for-each
       (lambda (width)
         (let* ((names (take '(a b c d e f) width))
                (environment '((a . #f) (b . 2) (c . 3) (d . 4) (e . 5) (f . 6)))
                (payload (vector names list)))
           (check-equal? (gerbil-ascent-expression-value payload environment)
                         (map cdr (take environment width)))
           (for-each
            (lambda (cut)
              (let ((calls 0) (scope (take environment cut)))
                (let (p (vector names (lambda args (set! calls (+ calls 1)) args)))
                  (check-equal? (outcome (lambda () (gerbil-ascent-expression-value p scope)))
                                (outcome (lambda () (old-expression p scope))))
                  (check-equal? calls 0))))
            (iota width)))) (iota 7)))
    (test-case "pattern extension keeps output order prior tail and detached pairs"
      (for-each
       (lambda (width)
         (let* ((names (map (lambda (n) (string->symbol (number->string n))) (iota width)))
                (matched (iota width)) (prior '((prior . #f)))
                (terms (list (cons 'pattern (vector names (lambda (_) matched)))))
                (next (gerbil-ascent-bind-row terms '(0) prior)))
           (check-equal? next (append (map cons names matched) prior))
           (check-equal? next (old-bind terms '(0) prior))
           (check-equal? (eq? (list-tail next width) prior) #t)
           (when (pair? matched)
             (set-car! matched 'changed)
             (check-equal? (cdar next) 0)))) '(0 1 2 16 64)))
    (test-case "malformed cyclic and false patterns retain rejection diagnostics"
      (let (cycle (list 1))
        (set-cdr! cycle cycle)
        (for-each
         (lambda (matched)
           (let (terms (list (cons 'pattern (vector '(x y) (lambda (_) matched)))))
             ;; Irritants can be cyclic: compare only messages in this case.
             (def (message call)
               (with-catch (lambda (failure) (error-message failure)) call))
             (check-equal? (message (lambda () (gerbil-ascent-bind-row terms '(0) [])))
                           (message (lambda () (old-bind terms '(0) []))))))
         (list #f 1 [] '(1) '(1 2 3) '(1 . 2) cycle))))
    (test-case "complete guard binding generator and head traces agree"
      (let* ((events [])
             (program (callback-program 4 2 (lambda (event) (set! events (cons event events)))))
             (old (old-evaluate program)) (old-events events))
        (set! events [])
        (let (new (gerbil-ascent-evaluate-program program))
          (check-equal? (callback-rows new) (callback-rows old))
          (check-equal? (list-sort (lambda (a b) (< (car a) (car b))) (callback-rows new))
                        '((2) (3) (4) (5) (6) (7) (8) (9)))
          (check-equal? events old-events))))
    (test-case "aggregate pattern projection and failures share the same boundary"
      (for-each
       (lambda (matched)
         (let* ((program
                 (gerbil-ascent-program
                  (list (gerbil-ascent-relation 'input 1 '((1) (2) (3)))
                        (gerbil-ascent-relation 'out 2 []))
                  (list (gerbil-ascent-rule
                         (list (gerbil-ascent-atom 'out
                                 (map gerbil-ascent-variable '(a b))))
                         (list (gerbil-ascent-aggregate '(a b) 'input
                                 (list (gerbil-ascent-variable 'x)) '(x)
                                 (lambda (rows) (list (list (length rows) #f)))
                                 (lambda (_) matched))))) 16 16 32))
                (a (outcome (lambda () (old-evaluate program))))
                (b (outcome (lambda () (gerbil-ascent-evaluate-program program)))))
           (if (equal? matched '(3 #f))
             (begin (check-equal? (callback-rows a) '((3 #f)))
                    (check-equal? (callback-rows b) '((3 #f))))
             (check-equal? b a))))
       (list '(3 #f) #f [] '(3) '(3 4 5) '(3 . 4))))
    (test-case "wide pattern complete solves and concurrent frames stay independent"
      (for-each
       (lambda (width)
         (let* ((program (pattern-program 16 width))
                (expected (map (lambda (n) (list (+ n (- width 1)))) (iota 16)))
                (old (old-evaluate program)) (new (gerbil-ascent-evaluate-program program)))
           (check-equal? (callback-rows new) (callback-rows old))
           (check-equal? (list-sort (lambda (a b) (< (car a) (car b))) (callback-rows new)) expected)
           (let (workers (map (lambda (_) (spawn (lambda () (callback-rows (gerbil-ascent-evaluate-program program))))) (iota 4)))
             (for-each (lambda (worker) (check-equal? (thread-join! worker) (callback-rows new))) workers))))
       '(1 2 16 64)))))
