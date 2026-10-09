;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/core/rule-bindings :gerbil-ascent/core/expression-plan
 (prefix-in :gerbil-ascent/t/performance/ordered-call/bindings-reference old-)
 (prefix-in :gerbil-ascent/t/performance/ordered-call/frame-reference old-))
(export call-input call-workflow call-expected)
(def (call-input arity count shape)
 (def procedure
  (case arity
   ((0) (lambda () 0)) ((1) (lambda (a) a)) ((2) (lambda (a b) (+ a b)))
   ((3) (lambda (a b c) (+ a b c))) ((4) (lambda (a b c d) (+ a b c d)))
   (else (lambda args (apply + args)))))
 (vector arity count shape procedure
  (map (lambda (i) (string->symbol (string-append "v" (number->string i)))) (iota arity))))
(def (call-workflow old? input)
 (with ([arity count shape procedure names] (vector->list input))
  (let* ((environment (map cons names (iota arity 1))) (frame (list->vector (iota arity 1)))
         (compiled (and (eq? shape 'frame)
          ((if old? old-gerbil-ascent-compile-frame-call gerbil-ascent-compile-frame-call) procedure (iota arity))))
         (sum 0))
   (for-each (lambda (i)
    ;; A fresh input observation per invocation prevents a cached-value shortcut.
    (when (> arity 0)
     (set-cdr! (car environment) (+ i 1))
     (vector-set! frame 0 (+ i 1)))
    (set! sum (+ sum
     (if compiled (compiled frame)
      ((if old? old-gerbil-ascent-call-with-bindings gerbil-ascent-call-with-bindings)
       procedure names environment "missing benchmark binding"))))) (iota count))
   sum)))
(def (call-expected input)
 (with ([arity count shape procedure names] (vector->list input))
  (if (zero? arity) 0
   (+ (quotient (* count (+ count 1)) 2)
      (* count (- (quotient (* arity (+ arity 1)) 2) 1))))))
