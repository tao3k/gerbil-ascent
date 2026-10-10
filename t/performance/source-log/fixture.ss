;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-program gerbil-ascent-relation)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session
                 gerbil-ascent-session-run gerbil-ascent-session-replace-sources!
                 gerbil-ascent-session-append-source!)
        (rename-in (only-in :gerbil-ascent/t/performance/source-log/reference-session gerbil-ascent-open-session)
                   (gerbil-ascent-open-session old-open)))
(export source-log-program source-log-request source-log-update source-log-result)
(def (source-log-program count size)
  (gerbil-ascent-program
   (map (lambda (n) (gerbil-ascent-relation (string->symbol (string-append "r" (number->string n)))
                                         1 (map list (iota size)))) (iota count))
   [] 65536 16 65536))
(def (source-log-request old? program (append? #f))
  (let (session ((if old? old-open gerbil-ascent-open-session) program))
    (gerbil-ascent-session-run session)
    (when append?
      (gerbil-ascent-session-append-source! session 'r1 '(9999))
      (gerbil-ascent-session-run session))
    session))
(def (source-log-result result count)
  (list (.ref result 'finished) (.ref result 'evaluation-path)
        (map (lambda (n) ((.ref result 'rows-of) (string->symbol (string-append "r" (number->string n)))))
             (iota count))))
(def (source-log-update session count)
  ;; Alternate replacements so each invocation performs a real transaction.
  (let* ((prior (gerbil-ascent-session-run session))
         (rows ((.ref prior 'rows-of) 'r0))
         (next (if (equal? rows '((7000))) '((7001)) '((7000))))
         (result (gerbil-ascent-session-replace-sources! session (list (cons 'r0 next)))))
    (source-log-result result count)))
