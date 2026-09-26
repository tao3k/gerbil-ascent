;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o))

(export gerbil-ascent-relation)

;;; Relations retain ordinary Scheme column values. Each row is a proper list;
;;; the evaluator owns set semantics and never mutates these source snapshots.
(def (gerbil-ascent-relation relation-name column-count source-rows)
  (unless (and (symbol? relation-name)
               (exact-integer? column-count) (<= 0 column-count)
               (list? source-rows))
    (error "invalid ASCENT relation declaration" relation-name column-count))
  (for-each
   (lambda (row)
     (unless (and (list? row) (= (length row) column-count))
       (error "invalid ASCENT relation row" relation-name row column-count)))
   source-rows)
  (.o (name relation-name) (arity column-count) (rows source-rows)))
