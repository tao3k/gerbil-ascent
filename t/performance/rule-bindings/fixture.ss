;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .ref)
        :gerbil-ascent/program/objects)
(export callback-program pattern-program callback-rows)
(def (callback-rows result)
  ((.ref result 'rows-of) 'out))
(def (callback-program size guards (trace #f))
  (def (event kind values) (when trace (trace (cons kind values))))
  (let ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y))
        (z (gerbil-ascent-variable 'z)))
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'input 2 (map (lambda (n) (list n (+ n 1))) (iota size)))
           (gerbil-ascent-relation 'out 1 []))
     (list (gerbil-ascent-rule
            (list (gerbil-ascent-atom 'out
                    (list (gerbil-ascent-expression '(z)
                            (lambda (n) (when trace (event 'head (list n))) (+ n 1))))))
            (append
             (list (gerbil-ascent-atom 'input (list x y)))
             (map (lambda (_)
                    (gerbil-ascent-guard '(x y)
                      (lambda (a b) (when trace (event 'guard (list a b))) (< a b)))) (iota guards))
             (list (gerbil-ascent-binding 'sum '(x y)
                     (lambda (a b) (when trace (event 'binding (list a b))) (+ a b)))
                   (gerbil-ascent-generator 'z '(sum)
                     (lambda (n) (when trace (event 'generator (list n))) (list n (+ n 1))))))))
     4096 4096 8192)))
(def (pattern-program size width)
  (let (names (map (lambda (n) (string->symbol (string-append "p" (number->string n)))) (iota width)))
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'input 1
             (map (lambda (n) (list (map (lambda (column) (+ n column)) (iota width)))) (iota size)))
           (gerbil-ascent-relation 'out 1 []))
     (list (gerbil-ascent-rule
            (list (gerbil-ascent-atom 'out (list (gerbil-ascent-variable (last names)))))
            (list (gerbil-ascent-atom 'input
                    (list (gerbil-ascent-pattern names (lambda (row) row)))))))
     4096 4096 8192)))
