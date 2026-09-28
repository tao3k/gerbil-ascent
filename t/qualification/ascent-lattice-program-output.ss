;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-lattice-program-fixture
                 ascent-lattice-fixture-evaluate
                 ascent-lattice-wide-evaluate
                 ascent-lattice-wide-source-evaluate))

(export main)

(def (main . _)
  (let* ((request (read))
         (mode (and (pair? request) (car request)))
         (result (case mode
                   ((wide) (ascent-lattice-wide-evaluate (cadr request)))
                   ((wide-source)
                    (ascent-lattice-wide-source-evaluate (cadr request)))
                   (else (ascent-lattice-fixture-evaluate request))))
         (rows ((.ref result 'rows-of)
                (if (memq mode '(wide wide-source)) 'best 'shortest))))
    (for-each
     (lambda (row)
       (display (car row))
       (for-each (lambda (column) (display #\tab) (display column))
                 (cdr row))
       (newline))
     rows)
    (display "END\n")))
