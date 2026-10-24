;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Physical index access owned by one engine. Only the canonical built-in
;;; provider has trusted hash buckets; every other receiver keeps dispatch.
(import (only-in "funs.ss" gerbil-ascent-index-build gerbil-ascent-index-extend!
                 gerbil-ascent-index-order! gerbil-ascent-index-row-snapshot)
        (only-in "funs.ss" gerbil-ascent-index-batch!)
        (only-in "provider.ss" gerbil-ascent-canonical-hash-index-provider?
                 gerbil-ascent-index-provider-build gerbil-ascent-index-provider-extend!
                 gerbil-ascent-index-provider-lookup))
(export gerbil-ascent-physical-index-build gerbil-ascent-physical-index-extend!
        gerbil-ascent-physical-index-rows gerbil-ascent-physical-index-single-rows)

;;; Planner columns and lookup-key widths are admitted before physical access.
;;; A one-column index uses raw scalar keys in a native equal? table. Public
;;; provider keys remain lists, and custom receivers retain their own index.
;; : (-> Index Rows Column Index)
(def (extend-scalar-index! index rows column)
  (gerbil-ascent-index-batch! index rows row (list-ref row column)))

;;; The engine selects this only for a canonical one-column physical index.
;;; Its scalar key is already evaluated; no list wrapper crosses this boundary.
;; : (-> Index Value Rows)
(def (gerbil-ascent-physical-index-single-rows index value)
  (or (hash-get index value) []))

;; : (-> IndexProvider Rows Columns Index)
(def (gerbil-ascent-physical-index-build provider rows columns)
  (if (gerbil-ascent-canonical-hash-index-provider? provider)
    (if (and (pair? columns) (null? (cdr columns)))
      (gerbil-ascent-index-order!
       (extend-scalar-index! (make-hash-table) rows (car columns)))
      (gerbil-ascent-index-build rows columns))
    ;; Open receivers get their own header, never admitted column metadata.
    (gerbil-ascent-index-provider-build provider
      (gerbil-ascent-index-row-snapshot rows) (map values columns))))

;; : (-> IndexProvider Index Rows Columns Index)
(def (gerbil-ascent-physical-index-extend! provider index rows columns)
  (if (gerbil-ascent-canonical-hash-index-provider? provider)
    (if (and (pair? columns) (null? (cdr columns)))
      (extend-scalar-index! index rows (car columns))
      (gerbil-ascent-index-extend! index rows columns))
    (gerbil-ascent-index-provider-extend! provider index
      (gerbil-ascent-index-row-snapshot rows) (map values columns))))

;; : (-> IndexProvider Index Key Rows)
(def (gerbil-ascent-physical-index-rows provider index key)
  (if (gerbil-ascent-canonical-hash-index-provider? provider)
    (if (and (pair? key) (null? (cdr key)))
      (gerbil-ascent-physical-index-single-rows index (car key))
      (or (hash-get index key) []))
    ;; Keep the evaluated key intact for the caller's coverage witness even
    ;; when the receiver mutates or retains its argument header.
    (let (matched (gerbil-ascent-index-provider-lookup provider index (map values key)))
      (unless (list? matched)
        (error "ASCENT index provider returned non-list rows" matched))
      matched)))
