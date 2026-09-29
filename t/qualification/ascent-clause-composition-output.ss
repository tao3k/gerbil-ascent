;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-open-session
                 gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-run
                 gerbil-ascent-count))

(export main)

(def (case-program edges)
  (ascent
   (relation edge (from to) edges)
   (relation blocked (from to))
   (relation root (node) '((0) (1) (2)))
   (relation candidate (from to score))
   (relation allowed (from to))
   (relation reach (from to))
   (relation reach-count (node total))
   ((blocked x y) <-- (edge x y)
    (if (x y) (even? (+ x y))))
   ((candidate x z score) <-- (edge x y)
    (for z (y) (list y (modulo (+ y 1) 3)))
    (if (x z) (not (= x z)))
    (let score (x z) (+ x z)))
   ((allowed x z) <-- (candidate x z score)
    (not (blocked x z)))
   ((reach x z) <-- (allowed x z))
   ((reach x z) <-- (reach x y) (allowed y z))
   ((reach-count x total) <-- (root x)
    (aggregate total gerbil-ascent-count () (reach x z)))
   (bounds 16 80 128)))

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
     '(blocked candidate allowed reach reach-count))))

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
