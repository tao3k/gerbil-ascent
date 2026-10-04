;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Frozen finite mapping boundary from 541d5b5; imports normalized only.
(import (only-in :gerbil-ascent/t/performance/finite-mapping/reference-objects
                 gerbil-ascent-relation gerbil-ascent-fragment)
        (rename-in (only-in :gerbil-ascent/program/objects gerbil-ascent-relation)
                   (gerbil-ascent-relation shared-core-relation))
        (only-in :gerbil-ascent/program/scheme-checked relational-scalar?)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-set-storage-provider))
(export relational-finite-rows relational-finite-view relational-source relational-source/shared-core)
(def (relational-copy-row row arity)
  (unless (and (list? row) (= (length row) arity)
               (andmap relational-scalar? row))
    (error "relational row has wrong arity or non-scalar value" row))
  (map identity row))
(def (relational-copy-rows rows arity)
  (unless (and (exact-integer? arity) (<= 0 arity) (list? rows))
    (error "invalid relational row signature" arity))
  (map (lambda (row) (relational-copy-row row arity)) rows))
(def (relational-finite-rows input-arity output-arity entries)
  (unless (and (exact-integer? input-arity) (<= 0 input-arity)
               (exact-integer? output-arity) (<= 0 output-arity)
               (list? entries))
    (error "invalid finite view signature"))
  (map
   (lambda (entry)
     (unless (and (list? entry) (= (length entry) 2))
       (error "finite view entry needs input and output rows" entry))
     (append (relational-copy-row (car entry) input-arity)
             (relational-copy-row (cadr entry) output-arity)))
   entries))
(def (relational-source name arity rows)
  (gerbil-ascent-relation
   name arity (relational-copy-rows rows arity)
   gerbil-ascent-hash-index-provider gerbil-ascent-set-storage-provider
   (make-list arity relational-scalar?)))

;;; The unchanged public copy boundary is controlled under the same Core.
;;; Full view construction above/below uses the frozen Core constructors.
(def (relational-source/shared-core name arity rows)
  (shared-core-relation
   name arity (relational-copy-rows rows arity)
   gerbil-ascent-hash-index-provider gerbil-ascent-set-storage-provider
   (make-list arity relational-scalar?)))
(def (relational-finite-view label input-arity output-arity entries)
  (unless (symbol? label)
    (error "finite view label must be a symbol" label))
  (let (handle (gensym 'view))
    (gerbil-ascent-fragment
     (list (relational-source
            handle (+ input-arity output-arity)
            (relational-finite-rows input-arity output-arity entries)))
     [] (list (cons label handle)) (list handle))))
