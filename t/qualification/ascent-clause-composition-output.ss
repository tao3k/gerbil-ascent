;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-open-session
                 gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-run)
        (only-in :gerbil-ascent/t/qualification/ascent-clause-composition-fixture
                 ascent-clause-composition-program))

(export main)

(def (case-program edges)
  (ascent-clause-composition-program
   edges '((0) (1) (2))
   (lambda (y) (modulo (+ y 1) 3))
   16 80 128))

(def (emit mask session edges)
  (gerbil-ascent-session-replace-source! session 'edge edges)
  (let (rows-of (.ref (gerbil-ascent-session-run session) 'rows-of))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display mask) (display #\tab) (display name)
          (for-each (lambda (column) (display #\tab) (display column)) row)
          (newline))
        (rows-of name)))
     '(blocked candidate allowed reach reach-count reach-max))))

(def (main . args)
  (unless (null? args)
    (error "ASCENT clause corpus reads cases from stdin"))
  (let (session (gerbil-ascent-open-session (case-program [])))
    (gerbil-ascent-session-run session)
    (for-each
     (lambda (entry)
       (emit (car entry) session (cadr entry)))
     (read)))
  (display "END\n")
  (force-output))
