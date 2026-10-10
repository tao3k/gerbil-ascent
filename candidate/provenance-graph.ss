;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/candidate/datum reasoning-bounded-data?)
        (only-in :gerbil-ascent/candidate/types
                 reasoning-snapshot-relations reasoning-candidate-facts
                 reasoning-candidate-rules)
        (only-in :gerbil-ascent/candidate/program candidate-variable?)
        (only-in :gerbil-ascent/candidate/funs candidate-fixed-clause candidate-bind-atom)
        (only-in :gerbil-ascent/candidate/provenance
                 candidate-positive-closed-absence positive-fixed-clause?
                 positive-proof? positive-proof-status positive-proof-nodes positive-proof-roots
                 positive-proof-snapshot-identity positive-proof-snapshot-generation
                 positive-proof-snapshot-digest positive-proof-candidate-digest positive-proof-query
                 proof-node? proof-node-id proof-node-relation proof-node-row
                 proof-node-kind proof-node-label proof-node-inputs))

(import (only-in "provenance-maintenance.ss"
                 candidate-make-provenance-maintenance provenance-maintenance?
                 provenance-maintenance-rows candidate-provenance-withdraw!
                 candidate-provenance-preview-withdraw candidate-provenance-compact
                 provenance-maintenance-size candidate-provenance-heights))

(export candidate-positive-provenance candidate-verify-positive-provenance
        positive-provenance? positive-provenance-status positive-provenance-witness
        positive-provenance-alternatives candidate-open-provenance-maintenance
        provenance-maintenance? provenance-maintenance-rows candidate-provenance-withdraw!
        candidate-provenance-preview-withdraw candidate-provenance-compact
        provenance-maintenance-size candidate-provenance-heights)

;; instantiate-head
;;   : (forall (a) (-> (Pair Symbol [(Or Symbol a)]) [(Pair Symbol a)] [(Or Symbol a)]))
;;   : (-> Head GroundBindings GroundRow)
;;   | doc m%
;;       Resolve a grounded head in term order, preserving literal values. Callers supply a binding for every head variable after finite positive grounding.
;;
;;       # Examples
;;
;;       ```scheme
;;       (instantiate-head '(out ?x 7) '((?x . #f)))
;;       ;; => '(#f 7)
;;       ```
;;     %
(def (instantiate-head head bindings)
  (map (lambda (term)
         (if (candidate-variable? term) (cdr (assq term bindings)) term))
       (cdr head)))

;;; Complete finite grounded derivation graph. A fact node may have several
;;; alternatives and rule alternatives may refer back to that same node.
;;; Cycles represent recursive equations, not an infinite list of proof trees.
(defstruct positive-provenance (status witness alternatives))

;; candidate-positive-provenance
;;   : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows Nat Nat PositiveProvenance)
;;   | doc m%
;;       Enumerate every grounded alternative after complete finite replay
;;       Cycles remain equations; exhausted enumeration returns bounded without alternatives.
;;     %
(def (candidate-positive-provenance snapshot spec digest native-status
                                   native-rows max-steps (edge-limit 4096))
  (unless (and (exact-integer? edge-limit) (> edge-limit 0))
    (error "invalid provenance edge limit" edge-limit))
  (let* ((witness (candidate-positive-closed-absence
                   snapshot spec digest native-status native-rows max-steps))
         (status (positive-proof-status witness)))
    (if (not (memq status '(complete closed-absent)))
      (make-positive-provenance status witness [])
      (let ((nodes (positive-proof-nodes witness))
            (by-row (make-hash-table))
            (by-relation (make-hash-table-eq))
            (seen-edges (make-hash-table))
            (alternatives []) (edge-count 0) (steps 0) (bounded? #f))
        ;; Index only this completed witness. Lists retain witness order for
        ;; grounding and budget probes; hash iteration never emits evidence.
        ;; Structural row keys match the former equal? lookup, and the first
        ;; node wins if the witness contains repeated relation/row keys.
        (for-each
         (lambda (node)
           (let* ((name (proof-node-relation node))
                  (key (cons name (proof-node-row node))))
             (unless (hash-get by-row key) (hash-put! by-row key node))
             (hash-put! by-relation name
                        (cons node (or (hash-get by-relation name) [])))))
         nodes)
        (hash-for-each
         (lambda (name bucket) (hash-put! by-relation name (reverse bucket)))
         by-relation)
        (def (node-for name row)
          (hash-get by-row (cons name row)))
        (def (add! output kind label inputs)
          (let (edge (list (proof-node-id output) kind label inputs))
            (unless (hash-get seen-edges edge)
              (if (>= edge-count edge-limit)
                (set! bounded? #t)
                (begin
                  (hash-put! seen-edges edge #t)
                  (set! edge-count (+ edge-count 1))
                  (set! alternatives (cons edge alternatives)))))))
        (for-each
         (lambda (entry)
           (for-each
            (lambda (row position)
              (unless bounded?
                (add! (node-for (car entry) row) 'source
                      (list (car entry) position) [])))
            (caddr entry) (iota (length (caddr entry)) 1)))
         (reasoning-snapshot-relations snapshot))
        (for-each
         (lambda (fact)
           (unless bounded?
             (add! (node-for (vector-ref fact 0) (vector-ref fact 1))
                   'candidate (vector-ref fact 2) [])))
         (reasoning-candidate-facts spec))
        (for-each
         (lambda (rule position)
           (def (walk remaining bindings inputs)
             (unless bounded?
               (if (null? remaining)
                 (let (output (node-for (car (vector-ref rule 0))
                                        (instantiate-head (vector-ref rule 0)
                                                          bindings)))
                   (unless output
                     (error "completed provenance closure is not closed"))
                   ;; Rule position distinguishes different rule occurrences
                   ;; even when their user-facing labels are identical.
                   (add! output 'rule (list position (vector-ref rule 2))
                         (reverse inputs)))
                 (let (clause (car remaining))
                   (if (positive-fixed-clause? clause)
                     (begin
                       (set! steps (+ steps 1))
                       (if (> steps max-steps)
                         (set! bounded? #t)
                         (let (next (candidate-fixed-clause clause bindings))
                           (when next (walk (cdr remaining) next inputs)))))
                     (for-each
                      (lambda (node)
                        (unless bounded?
                          (set! steps (+ steps 1))
                          (if (> steps max-steps)
                            (set! bounded? #t)
                            (let (next (candidate-bind-atom
                                        clause (proof-node-row node) bindings))
                              (when next
                                (walk (cdr remaining) next
                                      (cons (proof-node-id node) inputs)))))))
                      (or (hash-get by-relation (car clause)) [])))))))
           (walk (vector-ref rule 1) [] []))
         (reasoning-candidate-rules spec)
         (iota (length (reasoning-candidate-rules spec))))
        (make-positive-provenance (if bounded? 'bounded 'complete)
                                  witness
                                  (if bounded? [] (reverse alternatives)))))))

;;; Reconstruct every alternative; a missing edge is as invalid as an extra
;;; edge. Phase budgets cap both closure replay and complete enumeration.
;; candidate-verify-positive-provenance
;;   : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows PositiveProvenance Nat Nat Boolean)
;;   | doc m%
;;       Reconstruct the complete graph with independent byte/data caps
;;       Missing and extra alternatives reject as well as changed source/program bindings.
;;     %
(def (candidate-verify-positive-provenance snapshot spec digest native-status
                                          native-rows graph max-steps
                                          (edge-limit 4096))
  (and (exact-integer? edge-limit) (> edge-limit 0)
       (exact-integer? max-steps) (> max-steps 0)
       (positive-provenance? graph)
       (eq? (positive-provenance-status graph) 'complete)
       (let (edges (positive-provenance-alternatives graph))
         (and (reasoning-bounded-data? edges 131072 128)
              (list? edges) (<= (length edges) edge-limit)
              (let ((expected (candidate-positive-provenance
                               snapshot spec digest native-status native-rows
                               max-steps edge-limit))
                    (witness (positive-provenance-witness graph)))
                (and (eq? (positive-provenance-status expected) 'complete)
                     (positive-proof? witness)
                     (list? (positive-proof-nodes witness))
                     (<= (length (positive-proof-nodes witness)) 5120)
                     (reasoning-bounded-data? (positive-proof-roots witness) 131072 128)
                     (andmap
                      (lambda (node)
                        (and (proof-node? node)
                             (reasoning-bounded-data?
                              (list (proof-node-id node) (proof-node-kind node)
                                    (proof-node-relation node) (proof-node-row node)
                                    (proof-node-label node) (proof-node-inputs node))
                              131072 128)))
                      (positive-proof-nodes witness))
                     (equal? (positive-proof-status witness)
                             (positive-proof-status (positive-provenance-witness expected)))
                     (equal? (positive-proof-snapshot-identity witness)
                             (positive-proof-snapshot-identity
                              (positive-provenance-witness expected)))
                     (equal? (positive-proof-snapshot-generation witness)
                             (positive-proof-snapshot-generation
                              (positive-provenance-witness expected)))
                     (equal? (positive-proof-snapshot-digest witness)
                             (positive-proof-snapshot-digest
                              (positive-provenance-witness expected)))
                     (equal? (positive-proof-candidate-digest witness) digest)
                     (equal? (positive-proof-query witness)
                             (positive-proof-query
                              (positive-provenance-witness expected)))
                     (equal? (positive-proof-nodes witness)
                             (positive-proof-nodes
                              (positive-provenance-witness expected)))
                     (equal? (positive-proof-roots witness)
                             (positive-proof-roots
                              (positive-provenance-witness expected)))
                     (equal? edges
                             (positive-provenance-alternatives expected))))))))

;; candidate-open-provenance-maintenance
;;   : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows PositiveProvenance Nat Nat ProvenanceMaintenance)
;;   | doc m%
;;       Verify once and copy the graph into private retained state
;;       Future source withdrawals cannot mutate the supplied certificate.
;;     %
(def (candidate-open-provenance-maintenance snapshot spec digest native-status
                                           native-rows graph max-steps
                                           (edge-limit 4096))
  (unless (candidate-verify-positive-provenance
           snapshot spec digest native-status native-rows graph max-steps
           edge-limit)
    (error "unverified complete provenance graph"))
  (candidate-make-provenance-maintenance
   (positive-provenance-witness graph) (positive-provenance-alternatives graph)))
