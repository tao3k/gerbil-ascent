;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-hash-index-provider
                 gerbil-ascent-eqrel-storage-provider
                 gerbil-ascent-set-storage-provider)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-rule
                 gerbil-ascent-program gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/program/syntax ascent))

(export ascent-eqrel-fixture-evaluate
        ascent-storage-fixture-evaluate
        ascent-default-storage-evaluate)

(def (v name) (gerbil-ascent-variable name))
(def (a name . terms) (gerbil-ascent-atom name terms))

(def (ascent-storage-fixture-evaluate binary-seed grouped-seed storage-value
                                     (input-budget 64) (derived-budget 2048)
                                     (output-budget 2048))
  (gerbil-ascent-evaluate-program
   (gerbil-ascent-program
    (list
     (gerbil-ascent-relation 'binary-seed 2 binary-seed)
     (gerbil-ascent-relation 'grouped-seed 3 grouped-seed)
     (gerbil-ascent-relation
      'binary-eq 2 [] gerbil-ascent-hash-index-provider
      storage-value)
     (gerbil-ascent-relation
      'grouped-eq 3 [] gerbil-ascent-hash-index-provider
      storage-value)
     (gerbil-ascent-relation 'binary-output 2 [])
     (gerbil-ascent-relation 'grouped-output 3 []))
    (list
     (gerbil-ascent-rule
      (list (a 'binary-eq (v 'x) (v 'y)))
      (list (a 'binary-seed (v 'x) (v 'y))))
     (gerbil-ascent-rule
      (list (a 'grouped-eq (v 'g) (v 'x) (v 'y)))
      (list (a 'grouped-seed (v 'g) (v 'x) (v 'y))))
     (gerbil-ascent-rule
      (list (a 'binary-output (v 'x) (v 'y)))
      (list (a 'binary-eq (v 'x) (v 'y))))
     (gerbil-ascent-rule
      (list (a 'grouped-output (v 'g) (v 'x) (v 'y)))
      (list (a 'grouped-eq (v 'g) (v 'x) (v 'y)))))
    input-budget derived-budget output-budget)))

(def (ascent-eqrel-fixture-evaluate binary-seed grouped-seed)
  (ascent-storage-fixture-evaluate
   binary-seed grouped-seed gerbil-ascent-eqrel-storage-provider))

(def (ascent-default-storage-evaluate binary-seed grouped-seed)
  (gerbil-ascent-evaluate-program
   (ascent
    (default-storage gerbil-ascent-eqrel-storage-provider)
    (relation binary-seed (from to) binary-seed
              (index gerbil-ascent-hash-index-provider)
              (storage gerbil-ascent-set-storage-provider))
    (relation grouped-seed (group from to) grouped-seed
              (index gerbil-ascent-hash-index-provider)
              (storage gerbil-ascent-set-storage-provider))
    (relation binary-eq (from to))
    (relation grouped-eq (group from to))
    (relation binary-output (from to) []
              (index gerbil-ascent-hash-index-provider)
              (storage gerbil-ascent-set-storage-provider))
    (relation grouped-output (group from to) []
              (index gerbil-ascent-hash-index-provider)
              (storage gerbil-ascent-set-storage-provider))
    ((binary-eq x y) <-- (binary-seed x y))
    ((grouped-eq g x y) <-- (grouped-seed g x y))
    ((binary-output x y) <-- (binary-eq x y))
    ((grouped-output g x y) <-- (grouped-eq g x y))
    (bounds 64 2048 2048))))
