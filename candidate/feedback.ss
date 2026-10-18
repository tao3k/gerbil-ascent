;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/candidate/datum
                 reasoning-bounded-data? candidate-copy-pairs)
        (only-in :gerbil-ascent/candidate/program scalar?)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-receipt-bound? reasoning-receipt-status
                 reasoning-receipt-query reasoning-receipt-rows))
(export reasoning-compare-rows reasoning-compare-attempts reasoning-feedback?
        reasoning-feedback-status reasoning-feedback-reason
        reasoning-feedback-missing reasoning-feedback-extra)

;;; Detached finite observations, never a proof of intended meaning.
(defstruct reasoning-feedback (status reason missing extra) final: #t)

(def (refuse-feedback reason)
  (make-reasoning-feedback 'inconclusive reason [] []))

(def (receipt-feedback-reason snapshot candidate receipt)
  (cond ((not (reasoning-receipt-bound? receipt snapshot candidate)) 'unbound)
        ((not (eq? (reasoning-receipt-status receipt) 'complete))
         (reasoning-receipt-status receipt))
        (else #f)))

;;; Compare all queried rows as sets against a caller-owned finite reference.
;;; Binding and native completion precede comparison. Rejection, exhaustion,
;;; stale content and malformed references cannot become a semantic pass.
;;; The reference must use the receipt's full query tuple, including constants.
;;; Its authority and interpretation remain the caller's responsibility.
(def (reasoning-compare-rows snapshot candidate receipt expected)
  (let (reason (receipt-feedback-reason snapshot candidate receipt))
    (if reason (refuse-feedback reason)
        (compare-qualified-rows receipt expected))))

;;; Compare two already executed proposals, without rerunning either one.
;;; Both must complete against this exact source and submitted content. The
;;; full query datum (predicate, variables, constants and order) must agree.
;;; A gold program is caller supplied: agreement does not establish its intent
;;; fidelity, source completeness or proof validity.
(def (reasoning-compare-attempts snapshot candidate receipt
                                 reference-candidate reference-receipt)
  (let (reason (receipt-feedback-reason snapshot candidate receipt))
    (cond
     (reason (refuse-feedback reason))
     ((not (reasoning-receipt-bound? reference-receipt snapshot reference-candidate))
      (refuse-feedback 'reference-unbound))
     ((not (eq? (reasoning-receipt-status reference-receipt) 'complete))
      (refuse-feedback 'reference-incomplete))
     ((not (equal? (reasoning-receipt-query receipt)
                   (reasoning-receipt-query reference-receipt)))
      (refuse-feedback 'query-mismatch))
     (else (compare-qualified-rows receipt
                                   (reasoning-receipt-rows reference-receipt))))))

(def (compare-qualified-rows receipt expected)
  (cond
   ((not (and (reasoning-bounded-data? expected 16384 128)
              (list? expected)
              (let (arity (length (cdr (reasoning-receipt-query receipt))))
                (andmap (lambda (row)
                          (and (list? row) (= (length row) arity)
                               (andmap scalar? row))) expected))))
    (refuse-feedback 'invalid-reference))
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
