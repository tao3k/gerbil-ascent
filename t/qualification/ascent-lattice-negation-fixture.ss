;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/program/syntax ascent))

(export ascent-lattice-negation-program)

(def (ascent-lattice-negation-program edges)
  (ascent
   (relation edge (from to weight) edges)
   (relation origin (node) '((0)))
   (relation root (node) '((0) (1) (2) (3)))
   (lattice score (node distance) [] min)
   (relation cheap (node))
   (relation not-cheap (node))
   ((score node 0) <-- (origin node))
   ((score to (expr (distance weight) (+ distance weight))) <--
    (score from distance) (edge from to weight))
   ((cheap node) <-- (score node distance)
    (if (distance) (<= distance 2)))
   ((not-cheap node) <-- (root node) (not (cheap node)))
   (bounds 16 32 48)))
