;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-hash-index-provider
                 gerbil-ascent-eqrel-storage-provider
                 gerbil-ascent-trrel-storage-provider
                 gerbil-ascent-trrel-uf-storage-provider)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-rule
                 gerbil-ascent-program gerbil-ascent-evaluate-program))

(export ascent-byods-query-evaluate)

(def (v name) (gerbil-ascent-variable name))
(def (a name . terms) (gerbil-ascent-atom name terms))
(def (r head . body) (gerbil-ascent-rule (list head) body))

(def (ascent-byods-query-evaluate seed wanted (seed-extra []))
  (gerbil-ascent-evaluate-program
   (gerbil-ascent-program
    (list
     (gerbil-ascent-relation 'seed 3 seed)
     (gerbil-ascent-relation 'seed-extra 3 seed-extra)
     (gerbil-ascent-relation 'wanted 2 wanted)
     (gerbil-ascent-relation
      'eq 3 [] gerbil-ascent-hash-index-provider
      gerbil-ascent-eqrel-storage-provider)
     (gerbil-ascent-relation
      'tr 3 [] gerbil-ascent-hash-index-provider
      gerbil-ascent-trrel-storage-provider)
     (gerbil-ascent-relation
      'uf 3 [] gerbil-ascent-hash-index-provider
      gerbil-ascent-trrel-uf-storage-provider)
     (gerbil-ascent-relation 'eq-match 3 [])
     (gerbil-ascent-relation 'tr-match 3 [])
     (gerbil-ascent-relation 'uf-match 3 []))
    (list
     (r (a 'eq (v 'g) (v 'x) (v 'y))
        (a 'seed (v 'g) (v 'x) (v 'y)))
     (r (a 'tr (v 'g) (v 'x) (v 'y))
        (a 'seed (v 'g) (v 'x) (v 'y)))
     (r (a 'uf (v 'g) (v 'x) (v 'y))
        (a 'seed (v 'g) (v 'x) (v 'y)))
     (r (a 'eq (v 'g) (v 'x) (v 'y))
        (a 'seed-extra (v 'g) (v 'x) (v 'y)))
     (r (a 'tr (v 'g) (v 'x) (v 'y))
        (a 'seed-extra (v 'g) (v 'x) (v 'y)))
     (r (a 'uf (v 'g) (v 'x) (v 'y))
        (a 'seed-extra (v 'g) (v 'x) (v 'y)))
     (r (a 'eq-match (v 'g) (v 'x) (v 'y))
        (a 'eq (v 'g) (v 'x) (v 'y))
        (a 'wanted (v 'g) (v 'y)))
     (r (a 'tr-match (v 'g) (v 'x) (v 'y))
        (a 'tr (v 'g) (v 'x) (v 'y))
        (a 'wanted (v 'g) (v 'y)))
     (r (a 'uf-match (v 'g) (v 'x) (v 'y))
        (a 'uf (v 'g) (v 'x) (v 'y))
        (a 'wanted (v 'g) (v 'y))))
    64 256 320)))
