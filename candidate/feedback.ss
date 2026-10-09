;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/candidate/datum
                 reasoning-bounded-data? candidate-copy-pairs)
        (only-in :gerbil-ascent/candidate/program scalar?)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-receipt-bound? reasoning-receipt-status
                 reasoning-receipt-query reasoning-receipt-rows))
(export reasoning-compare-rows reasoning-feedback?
        reasoning-feedback-status reasoning-feedback-reason
        reasoning-feedback-missing reasoning-feedback-extra)

;;; Detached finite observations, never a proof of intended meaning.
(defstruct reasoning-feedback (status reason missing extra) final: #t)

;;; Compare all queried rows as sets against a caller-owned finite reference.
;;; Binding and native completion precede comparison. Rejection, exhaustion,
;;; stale content and malformed references cannot become a semantic pass.
;;; The reference must use the receipt's full query tuple, including constants.
;;; Its authority and interpretation remain the caller's responsibility.
(def (reasoning-compare-rows snapshot candidate receipt expected)
  (def (refuse reason)
    (make-reasoning-feedback 'inconclusive reason [] []))
  (cond
   ((not (reasoning-receipt-bound? receipt snapshot candidate))
    (refuse 'unbound))
   ((not (eq? (reasoning-receipt-status receipt) 'complete))
    (refuse (reasoning-receipt-status receipt)))
   ((not (and (reasoning-bounded-data? expected 16384 128)
              (list? expected)
              (let (arity (length (cdr (reasoning-receipt-query receipt))))
                (andmap (lambda (row)
                          (and (list? row) (= (length row) arity)
                               (andmap scalar? row))) expected))))
    (refuse 'invalid-reference))
   (else
    (let ((actual-set (make-hash-table)) (expected-set (make-hash-table))
          (actual []) (wanted []))
      (def (insert rows table)
        (let (unique [])
          (for-each (lambda (row)
                      (unless (hash-get table row)
                        (hash-put! table row #t)
                        (set! unique (cons row unique)))) rows)
          (reverse unique)))
      (set! actual (insert (reasoning-receipt-rows receipt) actual-set))
      (set! wanted (insert expected expected-set))
      (let ((missing (filter (lambda (row) (not (hash-get actual-set row))) wanted))
            (extra (filter (lambda (row) (not (hash-get expected-set row))) actual)))
        (make-reasoning-feedback
         (if (and (null? missing) (null? extra)) 'match 'mismatch) #f
         (candidate-copy-pairs missing) (candidate-copy-pairs extra)))))))
