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

(def (print-rows result (prefix []))
  (let (rows-of (.ref result 'rows-of))
    (for-each
     (lambda (name)
       (for-each
        (lambda (row)
          (for-each (lambda (field)
                      (display field)
                      (display #\tab))
                    prefix)
          (display name)
          (for-each (lambda (column) (display #\tab) (display column)) row)
          (newline))
        (rows-of name)))
     '(path0 path1 witness))))

(def (print-corpus cases)
  (let loop ((remaining cases) (index 0))
    (unless (null? remaining)
      (let* ((case (car remaining))
             (initial (car case))
             (added (cadr case))
             (session
              (gerbil-ascent-open-session
               (ascent-mutual-program initial)))
             (first (gerbil-ascent-session-run session))
             (first-rows-of (.ref first 'rows-of))
             (first-snapshot
              (map first-rows-of '(path0 path1 witness))))
        (print-rows first (list index 0))
        (for-each
         (lambda (edge)
           (gerbil-ascent-session-append-source! session 'edge edge))
         added)
        (print-rows (gerbil-ascent-session-run session)
                    (list index 1))
        (unless (equal? first-snapshot
                        (map first-rows-of '(path0 path1 witness)))
          (error "ASCENT retained session changed a prior snapshot" index)))
      (loop (cdr remaining) (+ index 1))))
  (display "END\n")
  (force-output))

(def (main . _)
  (let (request (read))
    (cond
     ((and (pair? request) (eq? (car request) 'corpus))
      (print-corpus (cadr request)))
     ((and (pair? request) (eq? (car request) 'session))
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
            (loop (cdr steps) (+ phase 1))))))
     (else
      (print-rows (ascent-mutual-evaluate request))))))
