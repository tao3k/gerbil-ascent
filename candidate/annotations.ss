;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil-ascent/candidate/datum candidate-copy-pairs)
        (only-in :gerbil-ascent/candidate/provenance proof-node-id proof-node-row
                 positive-proof-nodes positive-proof-roots)
        (only-in :gerbil-ascent/candidate/provenance-graph
                 candidate-positive-provenance positive-provenance-status
                 positive-provenance-witness positive-provenance-alternatives))
(export candidate-positive-counts positive-counts? positive-counts-status
        positive-counts-reason positive-counts-rows positive-counts-work)
(defstruct positive-counts (status reason rows work) final: #t)

;;; Unit annotations count all founded finite derivation trees represented by
;;; the complete grounded graph. Repeated body occurrences multiply separately;
;;; alternative rules and duplicate source occurrences add separately.
;;; Counts are private until a complete synchronous round is unchanged.
;; : (-> Snapshot InspectedCandidate Digest Status Rows Nat Nat Nat Nat PositiveCounts)
(def (candidate-positive-counts snapshot spec digest native-status native-rows
                                max-steps (max-work 100000) (count-limit 1000000)
                                (edge-limit 4096))
  (unless (and (exact-integer? max-work) (<= 1 max-work 1000000)
               (exact-integer? count-limit) (<= 1 count-limit 1000000000))
    (error "invalid provenance count limits" max-work count-limit))
  (let* ((graph (candidate-positive-provenance snapshot spec digest native-status
                                             native-rows max-steps edge-limit))
         (status (positive-provenance-status graph)))
    (if (not (eq? status 'complete))
      (make-positive-counts status 'incomplete-graph [] 0)
      (let/cc stop
        (let* ((witness (positive-provenance-witness graph))
               (nodes (positive-proof-nodes witness))
               (edges (positive-provenance-alternatives graph))
               (by-id (make-hash-table-eqv)) (work 0))
          (for-each (lambda (node) (hash-put! by-id (proof-node-id node) node)) nodes)
          (def (probe!)
            (when (>= work max-work)
              (stop (make-positive-counts 'bounded 'work-limit [] work)))
            (set! work (+ work 1)))
          (def (capped value)
            (when (> value count-limit)
              (stop (make-positive-counts 'bounded 'count-limit [] work)))
            value)
          ;; Every round is rebuilt from zero. Adding to previous counts would
          ;; count old proof trees again even on an acyclic graph.
          (let rounds ((prior (make-hash-table-eqv)))
            (let ((next (make-hash-table-eqv)) (changed? #f))
              (for-each
               (lambda (edge)
                 (probe!)
                 (let* ((output (car edge))
                        (amount (let product ((inputs (cadddr edge)) (acc 1))
                                  (if (null? inputs) acc
                                    (begin (probe!)
                                      (product (cdr inputs)
                                               (capped (* acc (or (hash-get prior (car inputs)) 0)))))))))
                   (hash-put! next output (capped (+ (or (hash-get next output) 0) amount))))) edges)
              (for-each (lambda (node)
                (probe!)
                (let (id (proof-node-id node))
                  (unless (= (or (hash-get prior id) 0) (or (hash-get next id) 0))
                    (set! changed? #t)))) nodes)
              (if changed? (rounds next)
                (make-positive-counts 'complete #f
                  (map (lambda (id)
                    (list (candidate-copy-pairs (proof-node-row (hash-ref by-id id)))
                          (or (hash-get next id) 0))) (positive-proof-roots witness)) work)))))))))
