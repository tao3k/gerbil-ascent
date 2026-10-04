;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/t/qualification/ascent-clause-composition-fixture
                 ascent-clause-composition-program))

(export main)

(def (main . args)
  (unless (null? args)
    (error "ASCENT clause scale reads its row count from stdin"))
  (let (size (read))
    (unless (and (exact-integer? size) (member size '(1000 10000)))
      (error "invalid ASCENT clause scale" size))
    (let* ((numbers (iota size))
           (edges (map (lambda (i)
                         (let (from (* 4 i))
                           (list from (if (even? i) from (+ from 1)))))
                       numbers))
           (roots (map (lambda (i) (list (* 4 i))) numbers))
           (result
            (gerbil-ascent-evaluate-program
             (ascent-clause-composition-program
              edges roots (lambda (y) (modulo (+ y 1) 3))
              (* 2 size) (* 10 size) (* 12 size))))
           (rows-of (.ref result 'rows-of)))
      (for-each
       (lambda (name)
         (for-each
          (lambda (row)
            (display name)
            (for-each (lambda (column) (display #\tab) (display column))
                      row)
            (newline))
          (rows-of name)))
       '(blocked candidate allowed reach reach-count reach-max))))
  (display "END\n")
  (force-output))
