;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-index-program-fixture
                 ascent-index-fixture-program)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program))

(export main)

(def (main . _)
  (for-each
   (lambda (row)
     (apply (lambda (from to)
              (display from)
              (display #\tab)
              (displayln to))
            row))
   ((.ref (gerbil-ascent-evaluate-program
           (ascent-index-fixture-program (read))) 'rows-of)
    'two-hop))
  (display "END\n"))
