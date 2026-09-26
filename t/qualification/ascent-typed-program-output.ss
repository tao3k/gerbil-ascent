;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-typed-program-fixture
                 ascent-typed-program-evaluate))

(export main)

(def (main . _)
  (let* ((result (apply ascent-typed-program-evaluate (read)))
         (rows ((.ref result 'rows-of) 'selected)))
    (for-each
     (lambda (row)
       (let (first? #t)
         (for-each
          (lambda (column)
            (unless first? (display #\tab))
            (set! first? #f)
            (display (if (boolean? column)
                       (if column "true" "false")
                       column)))
          row))
       (newline))
     rows)
    (display "END\n")))
