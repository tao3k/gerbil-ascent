;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-aggregate-program-fixture
                 ascent-derived-aggregate-fixture-evaluate))

(export main)

(def (main . args)
  (unless (null? args)
    (error "ASCENT derived aggregate fixture reads one snapshot from stdin"))
  (let* ((request (read))
         (result (ascent-derived-aggregate-fixture-evaluate
                  (car request) (cadr request)))
         (rows-of (.ref result 'rows-of)))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display name)
          (for-each (lambda (column) (display #\tab) (display column)) row)
          (newline))
        (rows-of name)))
     '(path reach-count))
    (display "END\n")))
