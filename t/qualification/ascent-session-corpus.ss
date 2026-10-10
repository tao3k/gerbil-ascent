;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Shared transport for retained-session Rust differential fixtures.
(import (only-in :gerbil/runtime/gambit
                 call-with-output-string display-exception)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-run))

(export ascent-session-corpus-run ascent-session-qualification)

;;; A fixture declares only its Session constructor and public projections.
;;; Syntax identifiers from the caller keep their lexical bindings; the entry
;;; point and transport are introduced together by this macro.
(defsyntax (ascent-session-qualification stx)
  (syntax-case stx ()
    ((_ entry make-session (name ...))
     (syntax
      (begin
        (export entry)
        (def (entry . args)
          (ascent-session-corpus-run
           make-session '(name ...) args)))))))

(def (result-rows result names)
  (let (rows-of (.ref result 'rows-of))
    (map rows-of names)))

(def (ascent-session-corpus-run make-session names args)
  (unless (null? args)
    (error "ASCENT retained corpus reads updates from stdin"))
  (let* ((request (read))
         (initial (car request))
         (session (make-session (car initial) (cadr initial)))
         (snapshots []))
    (def (capture phase)
      (let ((result (gerbil-ascent-session-run session)))
        (for-each
         (lambda (prior)
           (unless (equal? (result-rows (car prior) names) (cdr prior))
             (error "ASCENT prior result snapshot changed" phase)))
         snapshots)
        (let (rows (result-rows result names))
          (set! snapshots (cons (cons result rows) snapshots))
          (for-each
           (lambda (name relation-rows)
             (for-each
              (lambda (row)
                (display phase) (display #\tab) (display name)
                (for-each
                 (lambda (column) (display #\tab) (display column))
                 row)
                (newline))
              relation-rows))
           names rows))))
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
                 (error "ASCENT replacement diagnostic changed"
                        name failure))))
            (else (error "unknown ASCENT session update" update))))
        (capture phase)
        (loop (cdr updates) (+ phase 1)))))
  (display "END\n")
  (force-output))
