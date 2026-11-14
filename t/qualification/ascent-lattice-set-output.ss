;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-lattice-set-fixture
                 ascent-lattice-set-evaluate))

(export main)

(def (main . args)
  (unless (null? args)
    (error "ASCENT lattice set fixture reads seed and edge snapshots"))
  (let* ((seeds (read))
         (edges (read))
         (result (ascent-lattice-set-evaluate seeds edges)))
    (for-each
     (lambda (row)
       (for-each
        (lambda (tag)
          (display (car row))
          (display #\tab)
          (display tag)
          (newline))
        (cadr row)))
     ((.ref result 'rows-of) 'reach-tag))
    (display "END\n")
    (force-output)))
