;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-byods-lattice-fixture
                 ascent-byods-lattice-program)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-open-session
                 gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-run))

(export main)

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
     '(equivalent-output score cheap not-cheap not-count))))

(def (main . args)
  (unless (null? args)
    (error "ASCENT BYODS lattice corpus reads cases from stdin"))
  (let (session
        (gerbil-ascent-open-session
         (ascent-byods-lattice-program
          [] '((0 2) (1 3) (2 5)) '((0) (1) (2)) 32 128 160)))
    (gerbil-ascent-session-run session)
    (for-each
     (lambda (entry) (emit (car entry) session (cadr entry)))
     (read)))
  (display "END\n")
  (force-output))
