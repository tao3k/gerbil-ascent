;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Physical index access owned by one engine. Only the canonical built-in
;;; provider has trusted hash buckets; every other receiver keeps dispatch.
(import (only-in :gerbil-ascent/t/performance/index-build/reference-funs gerbil-ascent-index-build gerbil-ascent-index-extend!)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-canonical-hash-index-provider?
                 gerbil-ascent-index-provider-build gerbil-ascent-index-provider-extend!
                 gerbil-ascent-index-provider-lookup))
(export gerbil-ascent-physical-index-build gerbil-ascent-physical-index-extend!
        gerbil-ascent-physical-index-rows gerbil-ascent-physical-index-single-rows)

;;; Planner columns and lookup-key widths are admitted before physical access.
;;; A one-column index uses raw scalar keys in a native equal? table. Public
;;; provider keys remain lists, and custom receivers retain their own index.
;; : (-> Index Rows Column Index)
(def (extend-scalar-index! index rows column)
    (for-each
     (lambda (row)
       (let (key (list-ref row column))
         (hash-put! index key (cons row (or (hash-get index key) [])))))
     rows)
  index)

;;; The engine selects this only for a canonical one-column physical index.
;;; Its scalar key is already evaluated; no list wrapper crosses this boundary.
;; : (-> Index Value Rows)
(def (gerbil-ascent-physical-index-single-rows index value)
  (or (hash-get index value) []))

;; : (-> IndexProvider Rows Columns Index)
(def (gerbil-ascent-physical-index-build provider rows columns)
  (if (gerbil-ascent-canonical-hash-index-provider? provider)
    (if (and (pair? columns) (null? (cdr columns)))
      (extend-scalar-index!
       (make-hash-table) (reverse rows) (car columns))
      (gerbil-ascent-index-build rows columns))
    (gerbil-ascent-index-provider-build provider rows columns)))

;; : (-> IndexProvider Index Rows Columns Index)
(def (gerbil-ascent-physical-index-extend! provider index rows columns)
  (if (gerbil-ascent-canonical-hash-index-provider? provider)
    (if (and (pair? columns) (null? (cdr columns)))
      (extend-scalar-index! index rows (car columns))
      (gerbil-ascent-index-extend! index rows columns))
    (gerbil-ascent-index-provider-extend! provider index rows columns)))

;; : (-> IndexProvider Index Key Rows)
(def (gerbil-ascent-physical-index-rows provider index key)
  (if (gerbil-ascent-canonical-hash-index-provider? provider)
    (if (and (pair? key) (null? (cdr key)))
      (gerbil-ascent-physical-index-single-rows index (car key))
      (or (hash-get index key) []))
    (let (matched (gerbil-ascent-index-provider-lookup provider index key))
      (unless (list? matched)
        (error "ASCENT index provider returned non-list rows" matched))
      matched)))
