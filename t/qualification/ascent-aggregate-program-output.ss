;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-aggregate-program-fixture
                 ascent-aggregate-fixture-evaluate
                 ascent-aggregate-pattern-evaluate))

(export main)

(def (main . _)
  (let* ((values (read))
         (rows-of (.ref (ascent-aggregate-fixture-evaluate values) 'rows-of))
         (pattern-rows-of
          (.ref (ascent-aggregate-pattern-evaluate values) 'rows-of)))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display name)
          (display #\tab)
          (display (if (eq? name 'average)
                     (inexact->exact (round (car row)))
                     (car row)))
          (for-each (lambda (column) (display #\tab) (display column))
                    (cdr row))
          (newline))
        (rows-of name)))
     '(by-group minimum maximum total cardinality average custom))
    (for-each
     (lambda (row)
       (display "extrema-pair")
       (for-each (lambda (column) (display #\tab) (display column)) row)
       (newline))
     (pattern-rows-of 'extrema-pair))
    (display "END\n")))
