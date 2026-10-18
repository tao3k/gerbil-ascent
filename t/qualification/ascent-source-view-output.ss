;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Executed as source, independently of the native test library. This catches
;;; imports that compile away but fail in the interpreter's runtime loader.
(import :gerbil-ascent/core/relation-view :gerbil-ascent/table/trrel-uf
        :gerbil-ascent/program/objects
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-trrel-uf-storage-provider)
        (only-in :clan/poo/object .ref))
(def (assert-equal actual expected)
  (unless (equal? actual expected) (error "source view regression" actual expected)))
(def (main . args)
  (let (state (gerbil-ascent-trrel-uf-state))
    (gerbil-ascent-trrel-uf-insert! state '(0 1) 16)
    (let (old (gerbil-ascent-trrel-uf-freeze state))
      (gerbil-ascent-trrel-uf-insert! state '(1 0) 16)
      (assert-equal (relation-view-count old) 3)
      (assert-equal (gerbil-ascent-trrel-uf-view-lookup old '(0) '(1)) '((1 1)))
      (assert-equal (relation-view-count (gerbil-ascent-trrel-uf-freeze state)) 4)))
  (displayln "SOURCE-VIEW-OK frozen-cuts") (force-output)
  (let* ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y))
         (calls 0)
         (program (gerbil-ascent-program
           (list (gerbil-ascent-relation 'reach 2 '((0 1) (1 0))
                   gerbil-ascent-hash-index-provider gerbil-ascent-trrel-uf-storage-provider)
                 (gerbil-ascent-relation 'out 2 []))
           (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'out (list x y)))
             (list (gerbil-ascent-atom 'reach (list x y))
                   (gerbil-ascent-guard '(x y) (lambda (a b) (set! calls (+ calls 1)) #t)))))
           16 16 32))
         (result (gerbil-ascent-evaluate-program program)))
    (assert-equal (length ((.ref result 'rows-of) 'out)) 4)
    (assert-equal calls 4))
  (displayln "SOURCE-VIEW-OK callback-engine") (force-output))
