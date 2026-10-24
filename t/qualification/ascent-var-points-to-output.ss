;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/t/qualification/ascent-var-points-to-fixture
                 ascent-var-points-to-program))

(export main)

(def (main . args)
  (unless (null? args)
    (error "ASCENT points-to oracle reads four source relations from stdin"))
  (let* ((sources (read))
         (result (gerbil-ascent-evaluate-program
                  (apply ascent-var-points-to-program sources)))
         (rows-of (.ref result 'rows-of)))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display name)
          (for-each
           (lambda (value) (display #\tab) (display value))
           row)
          (newline))
        (rows-of name)))
     '(alias points-to))
    (displayln "END")
    (force-output)))
