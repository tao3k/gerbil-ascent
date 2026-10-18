;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/encoding/json
        :gerbil-ascent/candidate/feedback
        (only-in :gerbil-ascent/candidate/reasoning reasoning-source-snapshot
                 reasoning-attempt reasoning-receipt-status
                 reasoning-receipt-bound? reasoning-receipt-query reasoning-receipt-rows))
(export ascent-feedback-conformance-test)

(def (bit id place) (= (modulo (quotient id place) 2) 1))
(def (rows mask)
  (filter-map (lambda (value) (and (bit mask (expt 2 value)) (list value))) '(0 1)))
(def (row-mask rows)
  ;; Reject malformed, duplicate or out-of-domain observations, not just their
  ;; lossy bit-mask projection. Expected answers come from the foreign corpus.
  (let loop ((pending rows) (mask 0))
    (if (null? pending) mask
      (let (row (car pending))
        (unless (and (list? row) (= (length row) 1) (memv (car row) '(0 1))
                     (not (bit mask (expt 2 (car row)))))
          (error "feedback outside conformance row domain" rows))
        (loop (cdr pending) (+ mask (expt 2 (car row))))))))

(def ascent-feedback-conformance-test
  (test-suite "ExecutionFeedback foreign corpus against production Scheme"
    (test-case "all 1024 Quint and Lean input states with real executor receipts"
      (let ((corpus (call-with-input-file "t/qualification/fixtures/feedback/conformance.json" read-json))
            (sources (make-hash-table)) (receipts (make-hash-table)))
        (check-equal? (length corpus) 1024)
        (def (source a e generation)
          (let (key (list a e generation))
            (or (hash-get sources key)
                (let (snapshot
                      (reasoning-source-snapshot 'feedback-conformance generation
                        (list (list 'a 1 (rows a)) (list 'e 1 (rows e))
                              ;; Always overflow the unchanged tiny limit for
                              ;; incomplete states, including empty answer sets.
                              '(anchor 1 ((2) (3))))))
                  (hash-put! sources key snapshot) snapshot))))
        (def (attempt a e role bound complete same-query)
          (let (key (list a e role bound complete same-query))
            (or (hash-get receipts key)
                (let* ((p (list 'candidate '(relation answer 1)
                           (list 'rule '(answer ?value) (list role '?value))
                           (if same-query '(query answer ?value) '(query answer 9))
                           (if complete '(limits 16 64 128) '(limits 16 1 1))))
                       (r (reasoning-attempt (source a e (if bound 1 0)) p #f))
                       (entry (cons p r)))
                  (hash-put! receipts key entry) entry))))
        (for-each
         (lambda (vector id)
           (check-equal? (length vector) 4)
           (check-equal? (car vector) id)
           (let* ((a (modulo id 4)) (e (modulo (quotient id 4) 4))
                  (bound (bit id 16)) (complete (bit id 32)) (paired (bit id 64))
                  (reference-bound (bit id 128)) (reference-complete (bit id 256))
                  (same-query (bit id 512)) (current (source a e 1))
                  (actual (attempt a e 'a bound complete #t))
                  (reference (attempt a e 'e reference-bound reference-complete same-query)))
             ;; Verify the abstraction premises from actual public receipts.
             (check-equal? (reasoning-receipt-bound? (cdr actual) current (car actual)) bound)
             (check-equal? (eq? (reasoning-receipt-status (cdr actual)) 'complete) complete)
             (check-equal? (reasoning-receipt-bound? (cdr reference) current (car reference)) reference-bound)
             (check-equal? (eq? (reasoning-receipt-status (cdr reference)) 'complete) reference-complete)
             (when complete
               (check-equal? (row-mask (reasoning-receipt-rows (cdr actual))) a))
             (when (and reference-complete same-query)
               (check-equal? (row-mask (reasoning-receipt-rows (cdr reference))) e))
             (when (and complete reference-complete)
               (check-equal? (equal? (reasoning-receipt-query (cdr actual))
                                    (reasoning-receipt-query (cdr reference))) same-query))
             (let (feedback
                   (if paired
                     (reasoning-compare-attempts current (car actual) (cdr actual)
                                                (car reference) (cdr reference))
                     (reasoning-compare-rows current (car actual) (cdr actual) (rows e))))
               (check-equal? (reasoning-feedback-status feedback)
                             (list-ref '(inconclusive match mismatch) (cadr vector)))
               (check-equal? (row-mask (reasoning-feedback-missing feedback)) (caddr vector))
               (check-equal? (row-mask (reasoning-feedback-extra feedback)) (cadddr vector))))
           (when (zero? (modulo (+ id 1) 128))
             (displayln "FEEDBACK-CONFORMANCE " (+ id 1) "/1024") (force-output)))
         corpus (iota 1024))))))
