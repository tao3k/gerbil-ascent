;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Pure index algorithms. The evaluator owns cache invalidation.
(export gerbil-ascent-index-build gerbil-ascent-index-key)

(def (gerbil-ascent-index-key row columns)
  (map (lambda (column) (list-ref row column)) columns))

(def (gerbil-ascent-index-build rows columns)
  (let (index (make-hash-table))
    (for-each
     (lambda (row)
       (let (key (gerbil-ascent-index-key row columns))
         (hash-put! index key (cons row (or (hash-get index key) [])))))
     rows)
    index))
