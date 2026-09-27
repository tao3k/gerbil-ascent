;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-evaluate-program))

(export ascent-lattice-set-evaluate)

;;; Rust's Set lattice joins values at one key by union. Keep the Scheme
;;; representation as an ordinary list; only membership matters here.
(def (set-union left right)
  (foldl (lambda (value members)
           (if (member value members) members (cons value members)))
         left right))

(def (ascent-lattice-set-evaluate seeds edges)
  (gerbil-ascent-evaluate-program
   (ascent
    (relation seed (node tag) seeds)
    (relation edge (from to) edges)
    (lattice reach-tag (node tags) [] set-union)
    ((reach-tag node (expr (tag) (list tag))) <-- (seed node tag))
    ((reach-tag to (expr (tags) tags)) <--
     (reach-tag from tags) (edge from to))
    (bounds 64 256 320))))
