;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/core/ordered-call
 :gerbil-ascent/core/expression-plan :gerbil-ascent/core/rule-bindings
 (prefix-in :gerbil-ascent/t/performance/ordered-call/bindings-reference old-)
 (prefix-in :gerbil-ascent/t/performance/ordered-call/frame-reference old-))
(export ascent-ordered-call-test)
(def (outcome thunk)
 (with-catch (lambda (e) (list 'error (error-message e) (error-irritants e))) thunk))
(def ascent-ordered-call-test
 (test-suite "Shared ordered callback calling convention"
  (test-case "syntax binds reads once before callback and preserves multiple values"
   (let ((trace []) (next 'caller-next) (value 'caller-value) (input 'caller-input))
    (let-values (((first second)
     (dispatch-ordered-call (begin)
      (lambda (a b c) (set! trace (cons 'call trace)) (values (list a b c) next))
      '(0 1 2)
      (slot (begin (set! trace (cons slot trace)) (if (= slot 1) #f slot))))))
     (check-equal? first '(0 #f 2)) (check-equal? second 'caller-next))
    (check-equal? (reverse trace) '(0 1 2 call))
    (check-equal? (list next value input) '(caller-next caller-value caller-input))))
  (test-case "failed read prevents later inputs and callback execution"
   (let ((trace []) (called 0))
    (check-exception
     (dispatch-ordered-call (begin) (lambda args (set! called (+ called 1))) '(0 1 2 3)
      (slot (begin (set! trace (cons slot trace)) (when (= slot 1) (error "read failure")) slot)))
     (lambda (_) #t))
    (check-equal? (reverse trace) '(0 1)) (check-equal? called 0)))
  (test-case "zero through generic binding arities preserve first diagnostics"
   (for-each (lambda (width)
    (let* ((names (take '(a b c d e f) width)) (environment '((a . #f) (b . 2) (c . 3) (d . 4) (e . 5) (f . 6))))
     (check-equal? (gerbil-ascent-call-with-bindings list names environment "missing")
                  (old-gerbil-ascent-call-with-bindings list names environment "missing"))
     (for-each (lambda (missing)
      (let (bindings (filter (lambda (b) (not (eq? (car b) missing))) environment))
       (check-equal? (outcome (cut gerbil-ascent-call-with-bindings list names bindings "missing"))
                    (outcome (cut old-gerbil-ascent-call-with-bindings list names bindings "missing"))))) names))) (iota 7)))
  (test-case "published readers observe current frames and remain reentrant"
   (let ((frame (vector 1 2 3 4)) (nested #f) (call #f))
    (set! call (gerbil-ascent-compile-frame-call
     (lambda (a b c d)
      (if nested (list a b c d)
       (begin (set! nested #t) (vector-set! frame 0 9)
        (list (list a b c d) (call frame))))) '(0 1 2 3)))
    (check-equal? (call frame) '((1 2 3 4) (9 2 3 4)))
    (vector-set! frame 3 #f)
    (check-equal? (call frame) '(9 2 3 #f))))
  (test-case "bound values are captured before callback mutates the environment"
   (let ((environment (map cons '(a b c d) '(1 2 3 4))))
    (check-equal?
     (gerbil-ascent-call-with-bindings
      (lambda (a b c d) (set-cdr! (car environment) 9) (list a b c d))
      '(a b c d) environment "missing") '(1 2 3 4))
    (check-equal? (gerbil-ascent-call-with-bindings list '(d a b a) environment "missing") '(4 9 2 9))))
  (test-case "compiled calls retain baseline malformed slot diagnostics"
   (for-each (lambda (slots)
    (let ((a (old-gerbil-ascent-compile-frame-call list slots))
          (b (gerbil-ascent-compile-frame-call list slots)))
     (check-equal? (outcome (cut b '#(1 2))) (outcome (cut a '#(1 2))))))
    '(() (0) (1 0) (0 1 0) (0 1 0 1) (0 1 0 1 0) (0 3 1) (0 -1 1)))))
)
