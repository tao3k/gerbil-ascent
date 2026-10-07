;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .ref)
        :gerbil-ascent/applications/steensgaard
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program))
(export main)
(def (main . _)
  (let (cases (read))
    (for-each (lambda (inputs ordinal)
      (let (result (gerbil-ascent-evaluate-program (apply gerbil-ascent-steensgaard-program inputs)))
        (unless (.ref result 'finished) (error "Steensgaard oracle did not complete"))
        (for-each (lambda (row)
          (display ordinal) (display #\tab) (display (car row))
          (display #\tab) (display (cadr row)) (newline)) ((.ref result 'rows-of) 'vpt))
        (force-output))) cases (iota (length cases)))
    (display "END\n") (force-output)))
