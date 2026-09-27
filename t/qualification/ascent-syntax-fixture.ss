;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage
                 gerbil-ascent-set-storage-provider))

(export ascent-syntax-program ascent-syntax-evaluate)

(def (ascent-syntax-program edges anchor)
  (ascent
   (relation edge (from to) edges
             (index gerbil-ascent-hash-index-provider)
             (storage gerbil-ascent-set-storage-provider))
   (relation seed (node))
   (relation marker (node))
   (relation chosen (node))
   (relation packed (value) '((#(2 9)) (#(3 10)) (#(4))))
   (relation unpacked (from to))
   (relation tripled (value))
   (relation even-packed (value))
   (relation cross (left right))
   (fact (seed (lit anchor)))
   (facts (marker (lit anchor))
          (marker (lit (+ anchor 1))))
   ((chosen x) <--
    (or (and (seed x))
        (and (edge x y))))
   ((unpacked x y) <-- (packed value)
    (match (x y) (value) (vector x y)))
   ((tripled y) <-- (seed x) (let y (x) (* x 3)))
   ((even-packed x) <-- (packed value)
    (if-let (x y) (value) value (vector x y))
    (if (x) (even? x)))
   ((cross a b) <--
    (or (and (seed a)) (and (unpacked a ignored)))
    (or (and (seed b)) (and (marker b))))
   (bounds 16 16 32)))

(def (ascent-syntax-evaluate edges anchor)
  (gerbil-ascent-evaluate-program
   (ascent-syntax-program edges anchor)))
