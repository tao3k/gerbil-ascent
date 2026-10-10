;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/core/relation-view
 (prefix-in :gerbil-ascent/t/performance/explicit-selection/reference old-))
(export selection-input selection-workflow selection-expected)
(def (selection-input width count shape)
 (let* ((rows (map (lambda (id) (map (lambda (column) (if (zero? column) id column)) (iota width))) (iota count)))
        (columns (case shape
         ((empty) [])
         ((tiny) '(0))
         ((unordered) (reverse (iota width 0)))
         ((duplicate) (apply append (map (lambda (column) (list column column)) (iota (- width 1) 1))))
         (else (iota (- width 1) 1))))
        (key (if (eq? shape 'miss) (append (drop-right columns 1) '(-1)) columns)))
  (vector rows columns key)))
(def (selection-workflow old? input)
 (let ((rows (vector-ref input 0)) (columns (vector-ref input 1)) (key (vector-ref input 2)) (result []))
  ;; Keep each side's nominal view and stream types within its own publisher.
  (if old?
   (let (view (old-gerbil-ascent-explicit-view rows (length rows)))
    (old-gerbil-ascent-for-each-row (lambda (row) (set! result (cons row result)))
     (old-gerbil-ascent-view-select view columns key)))
   (let (view (gerbil-ascent-explicit-view rows (length rows)))
    (gerbil-ascent-for-each-row (lambda (row) (set! result (cons row result)))
     (gerbil-ascent-view-select view columns key))))
  (reverse result)))
;; Independent vector-based filtering, outside the measured lifecycle.
(def (selection-expected input)
 (filter (lambda (row)
  (let (fields (list->vector row))
   (andmap (lambda (column value) (equal? (vector-ref fields column) value))
    (vector-ref input 1) (vector-ref input 2)))) (vector-ref input 0)))
