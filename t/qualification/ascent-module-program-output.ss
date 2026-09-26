;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-module-source
                 ascent-origin-reach-program)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program))

(export main)

(def (main . _)
  (let* ((request (read))
         (origin (car request))
         (edges (cadr request))
         (result (gerbil-ascent-evaluate-program
                  (ascent-origin-reach-program edges origin))))
    (for-each
     (lambda (row)
       (display (car row))
       (display #\tab)
       (displayln (cadr row)))
     ((.ref result 'rows-of) 'reach))
    (display "END\n")))
