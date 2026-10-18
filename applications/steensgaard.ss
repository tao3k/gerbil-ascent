;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; B23 Steensgaard rules, aligned with the upstream application at
;;; 03f4f792442ecaf9e4f178a6a1b5840eab526388. Input and budget admission belong
;;; to the ordinary POO Program/Relation contracts; this module owns no state.
(import :gerbil-ascent/program/objects
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-eqrel-storage-provider
                 gerbil-ascent-set-storage-provider))
(export gerbil-ascent-steensgaard-program)

;; alloc/assign: (destination source); load: (destination base field);
;; store: (base field source). The explicit arm materializes equivalence laws.
(def (gerbil-ascent-steensgaard-program alloc assign load store
                                      (explicit? #f) (input-budget 1000000)
                                      (fact-budget 1000000) (output-budget 2000000))
  (let ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y))
        (p (gerbil-ascent-variable 'p)) (q (gerbil-ascent-variable 'q))
        (f (gerbil-ascent-variable 'f)) (z (gerbil-ascent-variable 'z)))
    (def (atom name . terms) (gerbil-ascent-atom name terms))
    (gerbil-ascent-program
      (list (gerbil-ascent-relation 'alloc 2 alloc)
            (gerbil-ascent-relation 'assign 2 assign)
            (gerbil-ascent-relation 'load 3 load)
            (gerbil-ascent-relation 'store 3 store)
            (gerbil-ascent-relation 'vpt 2 [] gerbil-ascent-hash-index-provider
              (if explicit? gerbil-ascent-set-storage-provider gerbil-ascent-eqrel-storage-provider)))
      (append
        (list (gerbil-ascent-rule (list (atom 'vpt x y)) (list (atom 'assign x y)))
              (gerbil-ascent-rule (list (atom 'vpt x y)) (list (atom 'alloc x y)))
              (gerbil-ascent-rule (list (atom 'vpt y p))
                (list (atom 'store x f y) (atom 'load p q f) (atom 'vpt x q))))
        (if explicit?
          (list (gerbil-ascent-rule (list (atom 'vpt y x) (atom 'vpt x x)) (list (atom 'vpt x y)))
                (gerbil-ascent-rule (list (atom 'vpt x z)) (list (atom 'vpt x y) (atom 'vpt y z))))
          []))
      input-budget fact-budget output-budget)))
