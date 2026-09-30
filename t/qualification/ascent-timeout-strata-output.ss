;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-open-session
                 gerbil-ascent-session-run
                 gerbil-ascent-session-run-timeout)
        (only-in :gerbil-ascent/program/syntax ascent))

(export main)

(def (main . args)
  (unless (null? args) (error "ASCENT timeout strata fixture takes no arguments"))
  (let* ((session
          (gerbil-ascent-open-session
           (ascent
            (relation edge (from to) '((0 1) (1 2) (2 3)))
            (relation blocked (node) '((2)))
            (relation path (from to))
            (relation allowed (from to))
            ((path x y) <-- (edge x y))
            ((path x z) <-- (path x y) (edge y z))
            ((allowed x y) <-- (path x y) (not (blocked y)))
            (bounds 4 32 40)))))
    (def (emit phase result)
      (display "finished") (display #\tab)
      (display phase) (display #\tab)
      (display (if (.ref result 'finished) 1 0)) (newline)
      (for-each
       (lambda (name)
         (for-each
          (lambda (row)
            (display phase) (display #\tab) (display name)
            (for-each (lambda (value) (display #\tab) (display value)) row)
            (newline))
          ((.ref result 'rows-of) name)))
       '(path allowed)))
    (emit "first" (gerbil-ascent-session-run-timeout session 0))
    (emit "second" (gerbil-ascent-session-run-timeout session 0))
    (emit "full" (gerbil-ascent-session-run session))
    (display "END\n")))
