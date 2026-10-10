;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-open-session
                 gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-run
                 gerbil-ascent-count)
        (only-in :gerbil-ascent/program/syntax ascent))

(export main)

(def (case-program edges)
  (ascent
   (relation edge (from to) edges)
   (relation seed (node value) '((0 2) (1 3) (2 5)))
   (relation root (node) '((0) (1) (2)))
   ;; Divisibility is a partial order. Scheme's standard lcm is its join.
   (lattice spectrum ((node integer?) (value integer?)) [] lcm)
   (relation six (node))
   (relation not-six (node))
   (relation six-count (total))
   ((spectrum node value) <-- (seed node value))
   ((spectrum to value) <-- (spectrum from value) (edge from to))
   ((six node) <-- (spectrum node value)
    (if (value) (zero? (modulo value 6))))
   ((not-six node) <-- (root node) (not (six node)))
   ((six-count total) <--
    (aggregate total gerbil-ascent-count () (six node)))
   (bounds 24 32 64)))

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
     '(spectrum six not-six six-count))))

(def (main . args)
  (unless (null? args)
    (error "ASCENT divisibility corpus reads cases from stdin"))
  (let (session (gerbil-ascent-open-session (case-program [])))
    (gerbil-ascent-session-run session)
    (for-each
     (lambda (entry)
       (emit (car entry) session (cadr entry)))
     (read)))
  (display "END\n")
  (force-output))
