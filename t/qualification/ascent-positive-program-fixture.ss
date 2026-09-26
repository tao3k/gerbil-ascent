;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        (only-in :gerbil-ascent/table/relation gerbil-ascent-relation)
        (only-in :gerbil-ascent/core/positive-program
                 gerbil-ascent-variable gerbil-ascent-literal
                 gerbil-ascent-atom gerbil-ascent-rule
                 gerbil-ascent-evaluate-positive-program))

(export ascent-positive-fixture-evaluate)

(def (v name) (gerbil-ascent-variable name))
(def (a name . terms) (gerbil-ascent-atom name terms))
(def (r head . body) (gerbil-ascent-rule head body))

(def (ascent-positive-fixture-evaluate edges (derived-limit 32))
  (gerbil-ascent-evaluate-positive-program
   (.o (relations
        (list (gerbil-ascent-relation 'edge 3 edges)
              (gerbil-ascent-relation 'node 1 '((1) (2) (3)))
              (gerbil-ascent-relation 'labelled 4 [])
              (gerbil-ascent-relation 'cycle 1 [])
              (gerbil-ascent-relation 'hot 1 [])
              (gerbil-ascent-relation 'reach 2 [])))
       (rules
        (list
         (r (a 'labelled (v 'x) (v 'z) (v 'first) (v 'second))
            (a 'edge (v 'x) (v 'y) (v 'first))
            (a 'edge (v 'y) (v 'z) (v 'second)))
         (r (a 'cycle (v 'x))
            (a 'edge (v 'x) (v 'x) (v 'label)))
         (r (a 'hot (v 'x))
            (a 'edge (v 'x) (v 'y) (gerbil-ascent-literal "a")))
         (r (a 'reach (v 'x) (v 'y))
            (a 'edge (v 'x) (v 'y) (v 'label)))
         (r (a 'reach (v 'x) (v 'z))
            (a 'reach (v 'x) (v 'y))
            (a 'edge (v 'y) (v 'z) (v 'label)))))
       (max-input-facts 16)
       (max-derived-facts derived-limit)
       (max-output-facts 64))))
