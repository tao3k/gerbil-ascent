;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-lattice-program-fixture
                 ascent-lattice-fixture-evaluate))

(export main)

(def (main . _)
  (for-each
   (lambda (row)
     (display (car row))
     (for-each (lambda (column) (display #\tab) (display column))
               (cdr row))
     (newline))
   ((.ref (ascent-lattice-fixture-evaluate (read)) 'rows-of) 'shortest))
  (display "END\n"))
