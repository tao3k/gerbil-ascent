;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o)
 :gerbil-ascent/program/index :gerbil-ascent/table/provider
 (prefix-in :gerbil-ascent/t/performance/provider-packet/reference old-))
(export packet-input packet-workflow packet-expected)
(def (packet-owner old? rows provider)
 (vector ((if old? old-gerbil-ascent-make-row-indexes gerbil-ascent-make-row-indexes)
  (vector rows) (vector rows) (vector (length rows)) (vector (length rows))
  (vector 0) (vector 0) (vector provider))))
(def (packet-input width count repeats)
 (let* ((rows (map (lambda (id) (cons 0 (cons id (make-list (- width 2) 3)))) (iota count)))
        (terms (cons '(literal . 0) (make-list (- width 1) '(wildcard . #f))))
        (atom (vector 0 terms '(0) terms (list (car terms))))
        (provider (.o (:: @ gerbil-ascent-hash-index-provider)
                       (.build-index (lambda (rows _columns) rows))
                       (.lookup-index (lambda (index _key) index))))
        (old (vector-ref (packet-owner #t rows provider) 0)) (new (vector-ref (packet-owner #f rows provider) 0))
        (input (vector old new atom repeats width count)))
  ;; Physical index construction and version witness admission are outside
  ;; timing. Both lanes execute the same complete warm lookup and consumption.
  ((old-row-indexes-rows old) atom [] #f #f)
  ((row-indexes-rows new) atom [] #f #f)
  input))
(def (packet-workflow old? input)
 (let* ((lookup (if old? (old-row-indexes-rows (vector-ref input 0))
                             (row-indexes-rows (vector-ref input 1))))
        (atom (vector-ref input 2)))
  (let repeat ((left (vector-ref input 3)) (total 0))
   (if (zero? left) total
    (repeat (- left 1)
     (foldl (lambda (row sum) (foldl + sum row)) total (lookup atom [] #f #f)))))))
(def (packet-expected input)
 (let ((width (vector-ref input 4)) (count (vector-ref input 5)))
  (* (vector-ref input 3) (+ (quotient (* count (- count 1)) 2)
                               (* count (- width 2) 3)))))
