;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/candidate/datum reasoning-bounded-data? candidate-copy-pairs)
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

(export candidate-positive-provenance candidate-verify-positive-provenance
        positive-provenance? positive-provenance-status positive-provenance-witness
        positive-provenance-alternatives candidate-open-provenance-maintenance
        provenance-maintenance? provenance-maintenance-rows candidate-provenance-withdraw!)

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
            (alternatives []) (steps 0) (bounded? #f))
        (def (node-for name row)
          (find (lambda (node)
                  (and (eq? name (proof-node-relation node))
                       (equal? row (proof-node-row node)))) nodes))
        (def (add! output kind label inputs)
          (let (edge (list (proof-node-id output) kind label inputs))
            (unless (member edge alternatives)
              (if (>= (length alternatives) edge-limit)
                (set! bounded? #t)
                (set! alternatives (cons edge alternatives))))))
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
                      (filter (lambda (node)
                                (eq? (car clause) (proof-node-relation node)))
                              nodes)))))))
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

;;; Validated, copied grounded support graph for deletion-only maintenance.
;;; Joins/rule grounding are paid at open time. Subsequent withdrawals use
;;; only dependency edges, preserving a last-completed result on failure.
(defstruct provenance-maintenance (nodes roots edges alive removed))

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
  (let* ((proof (positive-provenance-witness graph))
         (nodes (map (lambda (node)
                       (list (proof-node-id node)
                             (candidate-copy-pairs (proof-node-row node))))
                     (positive-proof-nodes proof))))
    (make-provenance-maintenance
     nodes (candidate-copy-pairs (positive-proof-roots proof))
     (candidate-copy-pairs (positive-provenance-alternatives graph))
     (map car nodes) [])))

;; provenance-maintenance-rows
;;   : (-> ProvenanceMaintenance Rows)
;;   | doc m%
;;       Copy the last completed query rows
;;       A failed withdrawal leaves these rows and source-occurrence state unchanged.
;;     %
(def (provenance-maintenance-rows state)
  (unless (provenance-maintenance? state)
    (error "expected provenance maintenance state"))
  (map (lambda (id)
         (candidate-copy-pairs (cadr (assq id (provenance-maintenance-nodes state)))))
       (filter (lambda (id) (memv id (provenance-maintenance-alive state)))
               (provenance-maintenance-roots state))))

;;; DRed on the finite grounded hypergraph: overdelete dependents of removed
;;; source occurrences, then rederive affected facts from remaining founded
;;; support. A self-cycle cannot seed its own rederivation. Multi-support
;;; can rederive overdeleted facts. Atomic publication follows both phases.
;; candidate-provenance-withdraw!
;;   : (-> ProvenanceMaintenance SourceOccurrences Nat (Values Rows Nat))
;;   | doc m%
;;       Overdelete affected support, then rederive from remaining founded alternatives
;;       Publish only after both bounded phases finish.
;;
;;       # Examples
;;
;;       ```scheme
;;       (let (before (provenance-maintenance-rows state))
;;         (let-values (((after work)
;;                       (candidate-provenance-withdraw! state [] 100000)))
;;           (equal? before after)))
;;       ;; => #t ; no selected source occurrences change the published rows
;;       ```
;;     %
(def (candidate-provenance-withdraw! state selectors (max-steps 100000))
  (unless (and (provenance-maintenance? state)
               (exact-integer? max-steps) (> max-steps 0)
               (reasoning-bounded-data? selectors 131072 128)
               (list? selectors))
    (error "invalid provenance withdrawal"))
  (let* ((edges (provenance-maintenance-edges state))
         (source-labels (map caddr (filter (lambda (edge)
                                            (eq? (cadr edge) 'source)) edges)))
         (removed (append (provenance-maintenance-removed state) selectors))
         (steps 0) (affected []))
    (for-each (lambda (selector)
                (unless (member selector source-labels)
                  (error "unknown provenance source occurrence" selector))) selectors)
    (def (probe!)
      (set! steps (+ steps 1))
      (when (> steps max-steps) (error "provenance withdrawal budget exceeded")))
    (def (removed-source? edge)
      (and (eq? (cadr edge) 'source) (member (caddr edge) removed)))
    (for-each (lambda (edge)
                (probe!)
                (when (and (eq? (cadr edge) 'source)
                           (member (caddr edge) selectors)
                           (not (memv (car edge) affected)))
                  (set! affected (cons (car edge) affected)))) edges)
    (let overdelete ()
      (let (changed? #f)
        (for-each
         (lambda (edge)
           (probe!)
           (when (and (eq? (cadr edge) 'rule)
                      (not (memv (car edge) affected))
                      (ormap (lambda (id) (memv id affected)) (cadddr edge)))
             (set! affected (cons (car edge) affected))
             (set! changed? #t))) edges)
        (when changed? (overdelete))))
    (let ((alive (filter (lambda (id) (not (memv id affected)))
                         (provenance-maintenance-alive state))))
      (let rederive ()
        (let (changed? #f)
          (for-each
           (lambda (edge)
             (probe!)
             (when (and (memv (car edge) affected)
                        (not (memv (car edge) alive))
                        (not (removed-source? edge))
                        (andmap (lambda (id) (memv id alive)) (cadddr edge)))
               (set! alive (cons (car edge) alive))
               (set! changed? #t))) edges)
          (when changed? (rederive))))
      (set! (provenance-maintenance-alive state) alive)
      (set! (provenance-maintenance-removed state) removed)
      (values (provenance-maintenance-rows state) steps))))
