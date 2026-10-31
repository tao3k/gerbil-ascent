;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Original constructors from 541d5b5 with frozen relation/fragment contracts.
(import (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop validate)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-set-storage-provider)
        (only-in :gerbil-ascent/t/performance/finite-mapping/reference-types
                 GerbilAscentRelationContract GerbilAscentFragmentContract))
(export gerbil-ascent-relation gerbil-ascent-fragment)
(def Relation. (.ref GerbilAscentRelationContract 'proto))
(def Fragment. (.ref GerbilAscentFragmentContract 'proto))
(def (gerbil-ascent-relation relation-name column-count source-rows
                             (provider-value gerbil-ascent-hash-index-provider)
                             (storage-value gerbil-ascent-set-storage-provider)
                             (field-predicates-value [])
                             (domain-descriptor #f))
  (unless (and (symbol? relation-name)
               (exact-integer? column-count) (<= 0 column-count)
               (list? source-rows)
               (list? field-predicates-value)
               (or (null? field-predicates-value)
                   (= (length field-predicates-value) column-count))
               (andmap procedure? field-predicates-value))
    (error "invalid ASCENT relation declaration" relation-name column-count))
  (for-each
   (lambda (row)
     (unless (and (list? row) (= (length row) column-count))
       (error "invalid ASCENT relation row" relation-name row column-count))
     (when (pair? field-predicates-value)
       (for-each
        (lambda (predicate value)
          (unless (predicate value)
            (error "ASCENT relation source field type mismatch"
                   relation-name row)))
        field-predicates-value row)))
   source-rows)
  (validate GerbilAscentRelationContract
            (.o (:: @ Relation.)
                name: relation-name arity: column-count rows: source-rows
                field-predicates: field-predicates-value
                checked-domain: domain-descriptor
                storage-kind: 'relation index-provider: provider-value
                storage-provider: storage-value)))
(def (fragment-export-resolver export-values)
  (unless (list? export-values)
    (error "invalid ASCENT fragment exports" export-values))
  (let loop ((remaining export-values) (seen []) (copied []))
    (if (null? remaining)
      (let (entries (reverse copied))
        (lambda (label)
          (let (entry (assq label entries))
            (unless entry
              (error "unknown relational fragment export" label))
            (cdr entry))))
      (let (entry (car remaining))
        (unless (and (pair? entry)
                     (symbol? (car entry))
                     (symbol? (cdr entry))
                     (not (memq (car entry) seen)))
          (error "invalid or duplicate ASCENT fragment export" entry))
        (loop (cdr remaining)
              (cons (car entry) seen)
              (cons (cons (car entry) (cdr entry)) copied))))))

(def (checked-source-handles relations source-handle-values)
  (unless (list? source-handle-values)
    (error "invalid ASCENT source handles" source-handle-values))
  (let loop ((remaining source-handle-values) (seen []))
    (if (null? remaining)
      (reverse seen)
      (let (name (car remaining))
        (unless (and (symbol? name)
                     (not (memq name seen))
                     (ormap (lambda (relation)
                              (eq? (.ref relation 'name) name))
                            relations))
          (error "invalid or duplicate ASCENT source handle" name))
        (loop (cdr remaining) (cons name seen))))))

(def (gerbil-ascent-fragment relation-values rule-values
                             (export-values []) (source-handle-values []))
  (validate GerbilAscentFragmentContract
            (.o (:: @ Fragment.)
                relations: relation-values rules: rule-values
                exports: (fragment-export-resolver export-values)
                source-handles:
                (checked-source-handles relation-values
                                        source-handle-values))))
