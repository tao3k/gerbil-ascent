;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil/runtime/gambit
                 call-with-output-string display-exception)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-count gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-run))

(export main)

(def derived-names '(reach allowed total))

(def (make-session edges blocked)
  (gerbil-ascent-open-session
   (ascent
    (relation edge (from to) edges)
    (relation blocked (from to) blocked)
    (relation reach (from to))
    (relation allowed (from to))
    (relation total (value))
    ((reach x y) <-- (edge x y))
    ((reach x z) <-- (reach x y) (edge y z))
    ((allowed x y) <-- (reach x y) (not (blocked x y)))
    ((total n) <--
     (aggregate n gerbil-ascent-count () (allowed _ _)))
    (bounds 12 100 100))))

(def (result-rows result)
  (let (rows-of (.ref result 'rows-of))
    (map rows-of derived-names)))

(def (print-result phase result)
  (for-each
   (lambda (name rows)
     (for-each
      (lambda (row)
        (display phase) (display #\tab) (display name)
        (for-each (lambda (column) (display #\tab) (display column)) row)
        (newline))
      rows))
   derived-names (result-rows result)))

(def (main . args)
  (unless (null? args)
    (error "ASCENT multi-source session reads updates from stdin"))
  (let* ((request (read))
         (initial (car request))
         (session (make-session (car initial) (cadr initial)))
         (snapshots []))
    (def (capture phase)
      (let (result (gerbil-ascent-session-run session))
        (for-each
         (lambda (prior)
           (unless (equal? (result-rows (car prior)) (cdr prior))
             (error "ASCENT earlier result snapshot changed" phase)))
         snapshots)
        (set! snapshots (cons (cons result (result-rows result)) snapshots))
        (print-result phase result)))
    (capture 0)
    (let loop ((updates (cdr request)) (phase 1))
      (unless (null? updates)
        (let* ((update (car updates))
               (operation (car update))
               (name (cadr update))
               (value (caddr update)))
          (case operation
            ((append)
             (gerbil-ascent-session-append-source! session name value))
            ((replace)
             (gerbil-ascent-session-replace-source! session name value))
            ((invalid-replace)
             (let (failure
                   (with-catch
                    (lambda (exception)
                      (call-with-output-string
                       (lambda (port)
                         (display-exception exception port))))
                    (lambda ()
                      (gerbil-ascent-session-replace-source!
                       session name value)
                      #f)))
               (unless (and (string? failure)
                            (string-contains failure
                                             "invalid ASCENT replacement source row"))
                 (error "ASCENT invalid replacement diagnostic changed"
                        name failure))))
            (else (error "unknown ASCENT session update" update))))
        (capture phase)
        (loop (cdr updates) (+ phase 1)))))
  (display "END\n")
  (force-output))
