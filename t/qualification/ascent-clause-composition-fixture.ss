;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/program/interface gerbil-ascent-count)
        (only-in :gerbil-ascent/program/syntax ascent))

(export ascent-clause-composition-program)

(def (ascent-clause-composition-program edges roots next-target
                                        input-limit derived-limit output-limit)
  (ascent
   (relation edge (from to) edges)
   (relation blocked (from to))
   (relation root (node) roots)
   (relation candidate (from to score))
   (relation allowed (from to))
   (relation reach (from to))
   (relation reach-count (node total))
   (relation reach-max (node target))
   ((blocked x y) <-- (edge x y)
    (if (x y) (even? (+ x y))))
   ((candidate x z score) <-- (edge x y)
    (for z (y) (list y (next-target y)))
    (if (x z) (not (= x z)))
    (let score (x z) (+ x z)))
   ((allowed x z) <-- (candidate x z score)
    (not (blocked x z)))
   ((reach x z) <-- (allowed x z))
   ((reach x z) <-- (reach x y) (allowed y z))
   ((reach-count x total) <-- (root x)
    (aggregate total gerbil-ascent-count () (reach x z)))
   ((reach-max x target) <-- (root x)
    (aggregate target
               (lambda (tuples)
                 (if (null? tuples)
                   []
                   (list (apply max (map car tuples)))))
               (z) (reach x z)))
   (bounds input-limit derived-limit output-limit)))
