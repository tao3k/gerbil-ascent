;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-index-program-fixture
                 ascent-index-fixture-program
                 ascent-composite-index-fixture-program
                 ascent-index-alist-provider)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program))

(export main)

(def (main . args)
  (let* ((make-program (if (member "composite" args)
                         ascent-composite-index-fixture-program
                         ascent-index-fixture-program))
         (program (if (member "alist" args)
                    (make-program (read) (ascent-index-alist-provider))
                    (make-program (read)))))
    (for-each
     (lambda (row)
       (display (car row))
       (for-each (lambda (column)
                   (display #\tab)
                   (display column))
                 (cdr row))
       (newline))
     ((.ref (gerbil-ascent-evaluate-program program) 'rows-of)
      'two-hop)))
  (display "END\n"))
