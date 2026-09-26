;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-rule
                 gerbil-ascent-program gerbil-ascent-evaluate-program))

(export ascent-mutual-program ascent-mutual-evaluate)

(def (v name) (gerbil-ascent-variable name))
(def (a name . terms) (gerbil-ascent-atom name terms))
(def (r head . body) (gerbil-ascent-rule (list head) body))

(def (ascent-mutual-program edges)
  (gerbil-ascent-program
   (list (gerbil-ascent-relation 'edge 2 edges)
         (gerbil-ascent-relation 'path0 2 [])
         (gerbil-ascent-relation 'path1 2 []))
   (list
    (r (a 'path1 (v 'x) (v 'z))
       (a 'path0 (v 'x) (v 'y)) (a 'edge (v 'y) (v 'z)))
    (r (a 'path0 (v 'x) (v 'z))
       (a 'path1 (v 'x) (v 'y)) (a 'edge (v 'y) (v 'z)))
    (r (a 'path0 (v 'x) (v 'y))
       (a 'edge (v 'x) (v 'y))))
   64 256 320))

(def (ascent-mutual-evaluate edges)
  (gerbil-ascent-evaluate-program (ascent-mutual-program edges)))
