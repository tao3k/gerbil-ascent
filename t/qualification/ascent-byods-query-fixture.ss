;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-hash-index-provider
                 gerbil-ascent-eqrel-storage-provider
                 gerbil-ascent-trrel-storage-provider
                 gerbil-ascent-trrel-uf-storage-provider)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-rule
                 gerbil-ascent-program gerbil-ascent-evaluate-program))

(export ascent-byods-query-program ascent-byods-query-evaluate)

(def (v name) (gerbil-ascent-variable name))
(def (a name . terms) (gerbil-ascent-atom name terms))
(def (r head . body) (gerbil-ascent-rule (list head) body))

;; The rules are immutable declarations. Partition tests replace source rows,
;; so constructing the same POO term and clause graph on every partition only
;; repeats contract validation without changing the program.
(def +byods-query-rules+
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
      (a 'wanted (v 'g) (v 'y)))))

(def +byods-query-result-relations+
  (list
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
   (gerbil-ascent-relation 'uf-match 3 [])))

(def +byods-query-template+
  (gerbil-ascent-program
   (append (list (gerbil-ascent-relation 'seed 3 [])
                 (gerbil-ascent-relation 'seed-extra 3 [])
                 (gerbil-ascent-relation 'wanted 2 []))
           +byods-query-result-relations+)
   +byods-query-rules+ 64 256 320))

(def (ascent-byods-query-program seed wanted (seed-extra []))
  ;; Validated source declarations replace only the template's source slots;
  ;; every execution still creates fresh Provider storage and row indexes.
  (.o (:: @ +byods-query-template+)
      relations:
      (append (list (gerbil-ascent-relation 'seed 3 seed)
                    (gerbil-ascent-relation 'seed-extra 3 seed-extra)
                    (gerbil-ascent-relation 'wanted 2 wanted))
              +byods-query-result-relations+)))

(def (ascent-byods-query-evaluate seed wanted (seed-extra []))
  (gerbil-ascent-evaluate-program
   (ascent-byods-query-program seed wanted seed-extra)))
