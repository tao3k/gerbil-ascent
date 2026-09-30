;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-hash-index-provider
                 gerbil-ascent-eqrel-storage-provider)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-count)
        (only-in :gerbil-ascent/program/syntax ascent))

(export ascent-byods-lattice-program)

(def (ascent-byods-lattice-program edges seeds roots
                                   input-limit derived-limit output-limit)
  (ascent
   (relation edge (from to) edges)
   (relation seed (node value) seeds)
   (relation root (node) roots)
   (relation equivalent (from to) []
             (index gerbil-ascent-hash-index-provider)
             (storage gerbil-ascent-eqrel-storage-provider))
   (relation equivalent-output (from to))
   (lattice score (node value) [] min)
   (relation cheap (node))
   (relation not-cheap (node))
   (relation not-count (total))
   ((equivalent x y) <-- (edge x y))
   ((equivalent-output x y) <-- (equivalent x y))
   ((score node value) <-- (seed node value))
   ((score to value) <-- (score from value) (equivalent from to))
   ((cheap node) <-- (score node value) (if (value) (<= value 2)))
   ((not-cheap node) <-- (root node) (not (cheap node)))
   ((not-count total) <--
    (aggregate total gerbil-ascent-count () (not-cheap node)))
   (bounds input-limit derived-limit output-limit)))
