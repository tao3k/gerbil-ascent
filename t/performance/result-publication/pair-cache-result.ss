;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Publish persistent ordered rows. A retained engine owns the optional cache;
;;; every publication owns its vector, while unchanged row spines may be shared.
(import (only-in :clan/poo/object .o))
(export gerbil-ascent-publish-rows gerbil-ascent-result)

;; : (-> RowsVector (Maybe PublicationCache) RowsVector)
(def (gerbil-ascent-publish-rows all cache)
  (if (not cache)
    (vector-map reverse all)
    (let* ((count (vector-length all)) (snapshots (make-vector count [])))
      (let loop ((index 0))
        (when (< index count)
          (let* ((rows (vector-ref all index)) (entry (vector-ref cache index))
                 (ordered (if (and entry (eq? rows (car entry)))
                            (cdr entry)
                            (let (fresh (reverse rows))
                              (vector-set! cache index (cons rows fresh))
                              fresh))))
            (vector-set! snapshots index ordered))
          (loop (+ index 1))))
      snapshots)))

;; : (-> Names RowsVector PositionLookup Boolean (Maybe RuleTicks) Result)
(def (gerbil-ascent-result names snapshots position-of complete? rule-ticks)
  (.o (relation-names (vector->list names))
      (finished complete?)
      (evaluation-path 'stratified-semi-naive)
      (rule-time-nanoseconds
       (and rule-ticks
            (map (lambda (ticks)
                   (quotient (* ticks 1000000000) (jiffies-per-second)))
                 (vector->list rule-ticks))))
      (relation-sizes
       (lambda ()
         (map (lambda (name rows) (cons name (length rows)))
              (vector->list names) (vector->list snapshots))))
      (rows-of (lambda (name) (vector-ref snapshots (position-of name))))))
