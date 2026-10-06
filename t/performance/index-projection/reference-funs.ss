;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Private index algorithms. The evaluator owns cache invalidation.

(export gerbil-ascent-index-build gerbil-ascent-index-extend! gerbil-ascent-index-order!
        gerbil-ascent-index-key)

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

;; : (-> Row Columns Nat Key)
(def (ordered-key row columns position)
  (if (null? columns)
    []
    (if (= position (car columns))
      (cons (car row) (ordered-key (cdr row) (cdr columns) (+ position 1)))
      (ordered-key (cdr row) columns (+ position 1)))))

;; : (-> Index (List Row) (List ColumnIndex) Index)
(def (gerbil-ascent-index-extend! index new-rows columns)
  ;; New batches are in insertion order; prepend keeps relation bucket order.
  ;; Select the projection once per batch, without per-row update closures.
  (let (ordered? (increasing-columns? columns))
    (for-each
     (lambda (row)
       (let (key (if ordered? (ordered-key row columns 0)
                     (gerbil-ascent-index-key row columns)))
         (hash-put! index key (cons row (or (hash-get index key) [])))))
     new-rows))
  index)
