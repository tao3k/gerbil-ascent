;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-rule
                 gerbil-ascent-program))

(export ascent-index-fixture-program)

(def (v name) (gerbil-ascent-variable name))
(def (a name . terms) (gerbil-ascent-atom name terms))

(def (chain-edges length)
  (let loop ((position 0) (rows []))
    (if (= position length)
      (reverse rows)
      (loop (+ position 1)
            (cons (list position (+ position 1)) rows)))))

(def (ascent-index-fixture-program (edge-count 50))
  (gerbil-ascent-program
   (list (gerbil-ascent-relation 'edge 2 (chain-edges edge-count))
         (gerbil-ascent-relation 'two-hop 2 []))
   (list (gerbil-ascent-rule
          (list (a 'two-hop (v 'x) (v 'z)))
          (list (a 'edge (v 'x) (v 'y))
                (a 'edge (v 'y) (v 'z)))))
   (+ edge-count 14) (+ edge-count 14) (* edge-count 3)))
