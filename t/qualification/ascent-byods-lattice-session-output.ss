;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil/runtime/gambit
                 call-with-output-string display-exception)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-byods-lattice-fixture
                 ascent-byods-lattice-program)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-run
                 gerbil-ascent-session-run-timeout))

(export main)

(def names '(equivalent-output score cheap not-cheap not-count))

(def (result-rows result)
  (let (rows-of (.ref result 'rows-of))
    (map rows-of names)))

(def (main . args)
  (unless (null? args)
    (error "ASCENT BYODS lattice session reads updates from stdin"))
  (let* ((request (read))
         (initial (car request))
         (session
          (gerbil-ascent-open-session
           (ascent-byods-lattice-program
            (car initial) (cadr initial) (caddr initial) 32 128 160)))
         (snapshots []))
    (def (save result phase)
      (for-each
       (lambda (prior)
         (unless (equal? (result-rows (car prior)) (cdr prior))
           (error "ASCENT prior BYODS lattice snapshot changed" phase)))
       snapshots)
      (set! snapshots (cons (cons result (result-rows result)) snapshots)))
    (def (capture phase)
      (let (partial (gerbil-ascent-session-run-timeout session 0))
        (save partial phase)
        (let (resumed (gerbil-ascent-session-run-timeout session 0))
          (save resumed phase)
          (let (full (gerbil-ascent-session-run session))
            (save full phase)
            (display phase) (display #\tab) (display "timeout")
            (display #\tab) (display (if (.ref partial 'finished) 1 0))
            (display #\tab) (display (if (.ref resumed 'finished) 1 0))
            (display #\tab) (display (if (.ref full 'finished) 1 0))
            (newline)
            (for-each
             (lambda (name)
               (for-each
                (lambda (row)
                  (display phase) (display #\tab) (display name)
                  (for-each (lambda (column)
                              (display #\tab) (display column)) row)
                  (newline))
                ((.ref full 'rows-of) name)))
             names)))))
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
                       (lambda (port) (display-exception exception port))))
                    (lambda ()
                      (gerbil-ascent-session-replace-source!
                       session name value)
                      #f)))
               (unless (and (string? failure)
                            (string-contains failure
                                             "invalid ASCENT replacement source row"))
                 (error "ASCENT replacement diagnostic changed"
                        name failure))))
            (else (error "unknown ASCENT session update" update))))
        (capture phase)
        (loop (cdr updates) (+ phase 1)))))
  (display "END\n")
  (force-output))
