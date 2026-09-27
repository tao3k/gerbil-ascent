;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-evaluate-program))

(export ascent-mutual-program ascent-mutual-evaluate)

(def (ascent-mutual-program edges)
  (ascent
   (relation edge (from to) edges)
   (relation path0 (from to))
   (relation path1 (from to))
   (relation witness (node))
   (((path1 x z) (witness z)) <-- (path0 x y) (edge y z))
   ((path0 x z) <-- (path1 x y) (edge y z))
   ((path0 x y) <-- (edge x y))
   (bounds 64 256 320)))

(def (ascent-mutual-evaluate edges)
  (gerbil-ascent-evaluate-program (ascent-mutual-program edges)))
