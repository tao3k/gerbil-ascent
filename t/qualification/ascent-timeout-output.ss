;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-open-session
                 gerbil-ascent-session-run
                 gerbil-ascent-session-run-timeout))

(export main)

(def (main . args)
  (unless (null? args) (error "ASCENT timeout fixture takes no arguments"))
  (let* ((edges (read))
         (session
          (gerbil-ascent-open-session
           (ascent
            (relation edge (from to) edges)
            (relation path (from to))
            ((path x y) <-- (edge x y))
            ((path x z) <-- (path x y) (edge y z))
            (bounds 64 4096 4160)))))
    (def (emit phase result)
      (display "finished") (display #\tab)
      (display phase) (display #\tab)
      (display (if (.ref result 'finished) 1 0)) (newline)
      (for-each
       (lambda (row)
         (display phase)
         (for-each (lambda (value) (display #\tab) (display value)) row)
         (newline))
       ((.ref result 'rows-of) 'path)))
    (emit "first" (gerbil-ascent-session-run-timeout session 0))
    (emit "second" (gerbil-ascent-session-run-timeout session 0))
    (emit "full" (gerbil-ascent-session-run session))
    (display "END\n")))
