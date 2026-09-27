;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-mutual-program-fixture
                 ascent-mutual-program ascent-mutual-evaluate)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-run))

(export main)

(def (print-rows result)
  (let (rows-of (.ref result 'rows-of))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (display name)
          (for-each (lambda (column) (display #\tab) (display column)) row)
          (newline))
        (rows-of name)))
     '(path0 path1 witness))))

(def (main . _)
  (let (request (read))
    (if (and (pair? request) (eq? (car request) 'session))
      (let (session (gerbil-ascent-open-session
                    (ascent-mutual-program (cadr request))))
        (let loop ((steps (cddr request)) (phase 0))
          (display "phase\t")
          (display phase)
          (newline)
          (print-rows (gerbil-ascent-session-run session))
          (unless (null? steps)
            (for-each
             (lambda (edge)
               (gerbil-ascent-session-append-source! session 'edge edge))
             (car steps))
            (loop (cdr steps) (+ phase 1)))))
      (print-rows (ascent-mutual-evaluate request)))))
