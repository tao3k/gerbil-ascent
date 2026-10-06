;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil-ascent/program/objects
  gerbil-ascent-program gerbil-ascent-relation gerbil-ascent-rule
  gerbil-ascent-atom gerbil-ascent-variable gerbil-ascent-expression
  gerbil-ascent-binding gerbil-ascent-guard))
(export expression-program)

;; : (-> Nat Nat Boolean Program)
(def (expression-program width stages expressions? (scope 2))
  (let* ((x (gerbil-ascent-variable 'x))
         (names (map (lambda (i) (string->symbol (string-append "v" (number->string i))))
                     (iota (+ stages 1))))
         (atom (lambda (name term) (gerbil-ascent-atom name (list term))))
         (rows (map list (iota width))))
    (gerbil-ascent-program
      (map (lambda (name) (gerbil-ascent-relation name 1 (if (eq? name 'v0) rows []))) names)
      (map
        (lambda (i)
          (let* ((source (list-ref names i)) (target (list-ref names (+ i 1)))
                 (variables (map (lambda (n) (string->symbol (string-append "b" (number->string n)))) (iota scope)))
                 (last-variable (car (reverse variables)))
                 (head (if expressions?
                         (gerbil-ascent-expression (list last-variable) (lambda (z) (+ z 1))) x))
                 (body (if expressions?
                         (append (list (atom source x))
                           (map (lambda (n name)
                             (let (prior (if (zero? n) 'x (list-ref variables (- n 1))))
                               (gerbil-ascent-binding name (list 'x prior)
                                 (lambda (x prior) (+ x prior 1)))))
                             (iota scope) variables)
                           (list (gerbil-ascent-guard (list 'x last-variable)
                             (lambda (x value) (= value (+ (* (+ scope 1) x) scope))))))
                         (list (atom source x)))))
            (gerbil-ascent-rule (list (atom target head)) body)))
        (iota stages))
      65536 65536 65536)))
