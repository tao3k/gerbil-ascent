;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-byods-lattice-fixture
                 ascent-byods-lattice-program)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program))

(export main)

(def (main . args)
  (unless (null? args)
    (error "ASCENT BYODS lattice scale reads its pair count from stdin"))
  (let (size (read))
    (unless (and (exact-integer? size) (member size '(1000 10000)))
      (error "invalid ASCENT BYODS lattice scale" size))
    (let* ((numbers (iota size))
           (edges (map (lambda (i) (list (* 2 i) (+ (* 2 i) 1)))
                       numbers))
           (seeds (append
                   (map (lambda (i) (list (* 2 i) 5)) numbers)
                   (map (lambda (i)
                          (list (+ (* 2 i) 1) (if (even? i) 2 3)))
                        numbers)))
           (roots (map (lambda (i) (list i)) (iota (* 2 size))))
           (result
            (gerbil-ascent-evaluate-program
             (ascent-byods-lattice-program
              edges seeds roots (* 5 size) (+ (* 14 size) 1)
              (+ (* 19 size) 1))))
           (rows-of (.ref result 'rows-of)))
      (for-each
       (lambda (name)
         (for-each
          (lambda (row)
            (display name)
            (for-each (lambda (column)
                        (display #\tab) (display column)) row)
            (newline))
          (rows-of name)))
       '(equivalent-output score cheap not-cheap not-count))))
  (display "END\n")
  (force-output))
