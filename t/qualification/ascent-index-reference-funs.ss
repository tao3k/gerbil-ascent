;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Private index algorithms. The evaluator owns cache invalidation.
(import (only-in :std/hash/misc hash-ensure-modify!))

(export gerbil-ascent-index-build gerbil-ascent-index-extend!
        gerbil-ascent-index-key)

;; : (-> Row (List ColumnIndex) Key)
(def (gerbil-ascent-index-key row columns)
  (map (lambda (column) (list-ref row column)) columns))

;; : (-> (List Row) (List ColumnIndex) Index)
(def (gerbil-ascent-index-build rows columns)
  (let (index (make-hash-table))
    (gerbil-ascent-index-extend! index (reverse rows) columns)))

;; : (-> Index (List Row) (List ColumnIndex) Index)
(def (gerbil-ascent-index-extend! index new-rows columns)
  ;; Rows are prepended to the relation. Process the new batch in insertion
  ;; order so each bucket has the same order as the current relation snapshot.
  (for-each
   (lambda (row)
     (hash-ensure-modify!
      index (gerbil-ascent-index-key row columns)
      (lambda () [])
      (lambda (bucket) (cons row bucket))))
   new-rows)
  index)
