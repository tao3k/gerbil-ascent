;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Qualification oracle only: execute the same original native Scheme forms.
(import :gerbil-ascent/interface/dsl-source
        :gerbil-ascent/program/interface
        (only-in :clan/poo/object .ref))
(export main)
(def (solve source rows)
  (let-values (((program descriptors exports) (ascent-load-dsl-sources (list source))))
    (let* ((session (gerbil-ascent-open-session program))
           (initial (gerbil-ascent-session-run-timeout session 10000000000))
           (_ (unless (.ref initial 'finished) (error "initial oracle deadline exhausted")))
           (_ (gerbil-ascent-session-replace-source! session 'input rows))
           (result (gerbil-ascent-session-run-timeout session 10000000000)))
      (unless (.ref result 'finished) (error "native expression oracle deadline exhausted"))
      (for-each (lambda (row) (display (car row)) (newline))
                ((.ref result 'rows-of) 'output))
      (display "--\n"))))
(def (main . arguments)
  (let loop ()
    (let (input (read))
      (unless (eof-object? input)
        (solve (car input) (cadr input))
        (loop)))))
