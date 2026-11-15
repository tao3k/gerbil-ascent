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
        gerbil-ascent-physical-index-rows gerbil-ascent-physical-index-single-rows
        gerbil-ascent-refill-cleared-index!
        gerbil-ascent-source-scalar-index-write! gerbil-ascent-source-scalar-index-rows)

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
      (gerbil-ascent-index-row-snapshot rows) (list-copy columns))))

;; Capacity follows the number of distinct keys after a replacement.
;; Copy occupied values directly, including freshly owned bucket spines.
;; : (forall (i) (-> i (Maybe Natural) i))
;; : (-> NativeIndex (Maybe PriorKeyCount) NativeIndex)
(def (compact-refilled-index index prior-keys)
  (let (keys (hash-length index))
    (if (and prior-keys (< (* 2 keys) prior-keys))
      (let (compact (make-hash-table size: (max 1 (- keys 1))))
        (hash-for-each (lambda (key bucket) (hash-put! compact key bucket)) index)
        compact)
      index)))

;; gerbil-ascent-source-scalar-index-write!
;; : (forall (i r) (-> i [r] Natural Boolean (Maybe Natural) i))
;; : (-> SourceScalarIndex ScalarRows Column Boolean (Maybe PriorKeyCount) SourceScalarIndex)
;; | doc m%
;;     Store the owned row directly for the first occurrence of a key.
;;     A second occurrence constructs a normal bucket. The source schema has
;;     a bound column and every row head is a scalar, which distinguishes
;;     an owned row from a list of rows. Restore order only for a fresh build.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-source-scalar-index-write! index '((0 a) (1 b)) 0 #t)
;;     ;; => an index that owns no extra bucket pairs for these rows
;;     ```
;;   %
(def (gerbil-ascent-source-scalar-index-write! index rows column
                                             (building? #f) (prior-keys #f))
  (let ((current #f) (repeated? #f))
    (def (prepend entry)
      (cond
       ((not entry) current)
       ((pair? (car entry)) (cons current entry))
       (else
        (set! repeated? #t)
        (list current entry))))
    (for-each
     (lambda (row)
       (let (key (list-ref row column))
         (set! current row)
         (hash-update! index key prepend #f)))
     rows)
    (if building?
      (let (ordered (compact-refilled-index index prior-keys))
        (when repeated?
          (hash-for-each
           (lambda (key entry)
             (when (pair? (car entry))
               (hash-put! ordered key (reverse! entry))))
           ordered))
        ordered)
      index)))

;; gerbil-ascent-source-scalar-index-rows
;; : (forall (i k r) (-> i k [r]))
;; : (-> SourceScalarIndex ScalarKey Rows)
;; | doc m%
;;     Convert a direct owned row to the traversal protocol at a hit.
;;     Multi-row buckets are already in traversal order.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-source-scalar-index-rows index 1)
;;     ;; => a singleton list containing the owned key 1 row
;;     ```
;;   %
(def (gerbil-ascent-source-scalar-index-rows index key)
  (let (entry (hash-get index key))
    (cond ((not entry) [])
          ((pair? (car entry)) entry)
          (else (list entry)))))

;; gerbil-ascent-refill-cleared-index!
;; : (forall (i r c) (-> i [r] [c] Natural i))
;; : (-> ClearedNativeIndex Rows Columns Natural Index)
;; | doc m%
;;     Refill a cleared, exclusively owned native index in source order.
;;     Compact when fewer than half the former keys remain. Fresh buckets
;;     belong to the new cut and are safe to reorder in place.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-refill-cleared-index! index '((0 a) (0 b)) '(0) 64)
;;     ;; => a compact native index with both rows in the key 0 bucket
;;     ```
;;   %
(def (gerbil-ascent-refill-cleared-index! index rows columns prior-keys)
  (if (and (pair? columns) (null? (cdr columns)))
    (extend-scalar-index! index rows (car columns))
    (gerbil-ascent-index-extend! index rows columns))
  (gerbil-ascent-index-order! (compact-refilled-index index prior-keys)))

;; : (-> IndexProvider Index Rows Columns Index)
(def (gerbil-ascent-physical-index-extend! provider index rows columns)
  (if (gerbil-ascent-canonical-hash-index-provider? provider)
    (if (and (pair? columns) (null? (cdr columns)))
      (extend-scalar-index! index rows (car columns))
      (gerbil-ascent-index-extend! index rows columns))
    (gerbil-ascent-index-provider-extend! provider index
      (gerbil-ascent-index-row-snapshot rows) (list-copy columns))))

;; : (-> IndexProvider Index Key Rows)
(def (gerbil-ascent-physical-index-rows provider index key)
  (if (gerbil-ascent-canonical-hash-index-provider? provider)
    (if (and (pair? key) (null? (cdr key)))
      (gerbil-ascent-physical-index-single-rows index (car key))
      (or (hash-get index key) []))
    ;; Keep the evaluated key intact for the caller's coverage witness even
    ;; when the receiver mutates or retains its argument header.
    (let (matched (gerbil-ascent-index-provider-lookup provider index (list-copy key)))
      (unless (list? matched)
        (error "ASCENT index provider returned non-list rows" matched))
      matched)))
