;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/iter in-range)
        (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-evaluate-program))

(export ascent-rule-fixture-program ascent-rule-fixture-evaluate)

(def (ascent-rule-fixture-program edges (derived-limit 32))
  (ascent
   (relation edge (from to label) edges)
   (relation node (value) '((1) (2) (3)))
   (relation labelled (from to first second))
   (relation cycle (node))
   (relation hot (node))
   (relation selected (from to))
   (relation choice (from to))
   (relation generated (value))
   (relation dependent (from to))
   (relation successor (from to))
   (relation blocked (from to))
   (relation allowed (from to))
   (relation denied (from to))
   (relation safe-reach (from to))
   (relation reach (from to))

   ((labelled x z first second) <-- (edge x y first) (edge y z second))
   ((cycle x) <-- (edge x x label))
   (((hot x) (selected x y)) <-- (edge x y label)
    (guard (label) (lambda (label) (equal? label "a"))))
   ((choice x y) <-- (node x)
    (for y () '(1 2 3))
    (guard (x y) (lambda (x y) (not (= x y)))))
   ((generated x) <--
    (for (x unused) () '#(#(1 2) #(2 3) #(3 4))))
   ((dependent x y) <-- (node x)
    (for y (x) (in-range 0 (- x 1))))
   ((successor x y) <-- (node x)
    (bind y (x) (lambda (x) (+ x 1))))
   ((blocked x y) <-- (edge x y label)
    (guard (label) (lambda (label) (equal? label "c"))))
   ((allowed x y) <-- (edge x y label) (not (blocked x y)))
   ((denied x y) <-- (edge x y label) (not (allowed x y)))
   ((safe-reach x y) <-- (allowed x y))
   ((safe-reach x z) <-- (safe-reach x y) (allowed y z))
   ((reach x y) <-- (edge x y label))
   ((reach x z) <-- (reach x y) (edge y z label))
   (bounds 16 derived-limit 64)))

(def (ascent-rule-fixture-evaluate edges (derived-limit 32))
  (gerbil-ascent-evaluate-program
   (ascent-rule-fixture-program edges derived-limit)))
