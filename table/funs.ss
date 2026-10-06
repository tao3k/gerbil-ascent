;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Private index algorithms. The evaluator owns cache invalidation.

(export gerbil-ascent-index-build gerbil-ascent-index-extend! gerbil-ascent-index-order!
        gerbil-ascent-index-key gerbil-ascent-index-row-snapshot)

;;; Copy admitted outer/row spines while preserving field value identity.
;;; Custom lookup callers must finish bounded row-shape admission first.
(def (gerbil-ascent-index-row-snapshot rows)
  (map (lambda (row) (map values row)) rows))

;; : (-> Row (List ColumnIndex) Key)
(def (gerbil-ascent-index-key row columns)
  (map (lambda (column) (list-ref row column)) columns))

;; : (-> (List Row) (List ColumnIndex) Index)
(def (gerbil-ascent-index-build rows columns)
  (let (index (make-hash-table))
    (gerbil-ascent-index-extend! index rows columns)
    (gerbil-ascent-index-order! index)))

;; gerbil-ascent-index-order!
;; : (forall (k r) (-> (HashTable k [r]) (HashTable k [r])))
;; : (-> FreshOwnedBuckets OrderedIndex)
;; | doc m%
;;     Restore source order only in freshly constructed private bucket spines.
;;     Rows and keys remain caller-owned; existing published indexes must never
;;     pass through this operation. Singleton buckets already have source order.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-index-order! fresh-index)
;;     ;; => the same index with each owned bucket in source order
;;     ```
;;   %
(def (gerbil-ascent-index-order! index)
  (hash-for-each
   (lambda (key rows)
     (when (pair? (cdr rows))
       (hash-put! index key (reverse! rows)))) index)
  index)

;;; Ordered planner columns can be projected with one forward row cursor.
;;; Unordered or repeated columns retain the public arbitrary-column semantics.
;; : (-> Columns Boolean)
(def (increasing-columns? columns)
  (let loop ((remaining columns) (prior -1))
    (or (null? remaining)
        (and (> (car remaining) prior)
             (loop (cdr remaining) (car remaining))))))

;;; Distances belong to this batch, never a cache of caller-owned columns.
;;; The next cursor starts immediately after the preceding selected value.
;; : (-> Columns (List Nat))
(def (column-steps columns)
  (let loop ((remaining columns) (position 0))
    (if (null? remaining)
      []
      (cons (inexact->exact (- (car remaining) position))
            (loop (cdr remaining) (+ (car remaining) 1))))))

;; : (-> Row (List Nat) Key)
(def (stepped-key row steps)
  (if (null? steps)
    []
    (let (selected (list-tail row (car steps)))
      (cons (car selected) (stepped-key (cdr selected) (cdr steps))))))

;; : (-> Index (List Row) (List ColumnIndex) Index)
(def (gerbil-ascent-index-extend! index new-rows columns)
  ;; New batches are in insertion order; prepend keeps relation bucket order.
  ;; Select the complete loop once. Ordered rows need no column comparison,
  ;; position counter or shape branch while traversing their key values.
  ;; Native hash-update! invokes its callback synchronously and does not retain
  ;; it. One private slot supplies the row to a single batch callback, keeping
  ;; lexical bindings stable and avoiding one captured closure per input row.
  ;; Prepending creates a fresh spine; no previously returned bucket is edited.
  (let* ((row-slot (vector #f))
         (prepend-row (lambda (bucket) (cons (vector-ref row-slot 0) (or bucket [])))))
    (if (increasing-columns? columns)
      (let (steps (column-steps columns))
        (for-each
         (lambda (row)
           (let (key (stepped-key row steps))
             (vector-set! row-slot 0 row)
             (hash-update! index key prepend-row #f)))
         new-rows))
      (for-each
       (lambda (row)
         (let (key (gerbil-ascent-index-key row columns))
           (vector-set! row-slot 0 row)
           (hash-update! index key prepend-row #f)))
       new-rows)))
  index)
