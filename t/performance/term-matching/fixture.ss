;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/core/rule-bindings
 (prefix-in :gerbil-ascent/t/performance/term-matching/reference old-))
(export term-input term-workflow term-expected)
(def (term-input width count shape)
 (let* ((names (map (lambda (n) (string->symbol (string-append "v" (number->string n)))) (iota width)))
        (terms (case shape
         ((pattern) (list (cons 'pattern (vector names identity))))
         (else (map (lambda (name) (cons 'fresh-variable name)) names))))
        (row (if (eq? shape 'pattern) (list (iota width)) (iota width)))
        (heads (map (lambda (name) (cons 'variable name)) names)))
  (vector terms row heads count)))
(def (term-workflow old? input)
 (with ([terms row heads count] (vector->list input))
  (let (sum 0)
   (for-each (lambda (_)
    (let* ((bindings ((if old? old-gerbil-ascent-bind-row gerbil-ascent-bind-row) terms row []))
           (result ((if old? old-gerbil-ascent-head-row gerbil-ascent-head-row) heads bindings)))
     (set! sum (+ sum (foldl + 0 result))))) (iota count)) sum)))
(def (term-expected input)
 (* (vector-ref input 3) (foldl + 0 (if (eq? (caar (vector-ref input 0)) 'pattern)
   (car (vector-ref input 1)) (vector-ref input 1)))))
