;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; A bounded proof interpreter for inspected positive rules with fixed
;;; scalar filters and computations.
;;; Its result is checked against the completed native query before use.
;;; Node inputs always refer to earlier nodes, so the list is a finite DAG.
(import (only-in :gerbil-ascent/candidate/datum candidate-copy-pairs)
        (only-in :gerbil-ascent/candidate/certificate-limits
                 make-certificate-material-budget certificate-material-reserve!
                 certificate-for-each-while bounded-list-length)
        (only-in :gerbil-ascent/candidate/types
                 reasoning-snapshot-identity reasoning-snapshot-generation
                 reasoning-snapshot-digest reasoning-snapshot-relations
                 reasoning-snapshot-valid?
                 reasoning-candidate-facts reasoning-candidate-rules
                 reasoning-candidate-query reasoning-candidate-limits)
        (only-in :gerbil-ascent/candidate/program candidate-variable?)
        (only-in :gerbil-ascent/candidate/funs
                 candidate-same-row-set? candidate-schema-of
                 candidate-bind-atom candidate-fixed-clause))

(export candidate-positive-proof candidate-positive-closed-absence
        candidate-verify-positive-proof
        positive-rule-body? positive-fixed-clause?
        positive-proof? positive-proof-status
        positive-proof-snapshot-identity positive-proof-snapshot-generation
        positive-proof-snapshot-digest positive-proof-candidate-digest
        positive-proof-query positive-proof-work-budget
        positive-proof-nodes positive-proof-roots
        proof-node? proof-node-id proof-node-kind proof-node-relation
        proof-node-row proof-node-label proof-node-inputs)

(defstruct positive-proof
  (status snapshot-identity snapshot-generation snapshot-digest
          candidate-digest query work-budget nodes roots))
(defstruct proof-node (id kind relation row label inputs))
;;; One replay owns these queue spines and row indexes. Only proof nodes are
;;; published; a queue is extended only between completed grounding rounds.
;; : (-> ProofNodes (Maybe Pair) RowIndex ProofRelation)
(defstruct proof-relation (nodes tail members))
(def (positive-atom? atom)
  (and (pair? atom) (symbol? (car atom))
       (not (memq (car atom) '(not where compute reduce)))))

(def (positive-fixed-clause? clause)
  (and (list? clause) (pair? clause)
       (case (car clause)
         ((where)
          (and (= (length clause) 2)
               (list? (cadr clause))
               (pair? (cadr clause))
               (case (caadr clause)
                 ((even?) (= (length (cadr clause)) 2))
                 ((<) (= (length (cadr clause)) 3))
                 (else #f))))
         ((compute)
          (and (= (length clause) 3)
               (candidate-variable? (cadr clause))
               (list? (caddr clause))
               (pair? (caddr clause))
               (case (caaddr clause)
                 ((identity) (= (length (caddr clause)) 2))
                 ((+) (= (length (caddr clause)) 3))
                 (else #f))))
         (else #f))))

(def (positive-rule-body? rule)
  (andmap (lambda (clause)
            (or (positive-atom? clause)
                (positive-fixed-clause? clause)))
          (vector-ref rule 1)))

(def (positive-rules? spec)
  (andmap
   positive-rule-body?
   (reasoning-candidate-rules spec)))

(def (instantiate-head head bindings)
  (map (lambda (term)
         (if (candidate-variable? term)
           (cdr (assq term bindings))
           term))
       (cdr head)))
;;; max-steps bounds body-row probes and fixed-clause evaluations,
;;; including unsuccessful unifications and filters.
;;; The proposal's derived-fact limit separately bounds the DAG size.
;;; A complete proof is returned only when the native solve completed and
;;; this independent interpreter reproduces every native query row.
;;; No absence claim is made here.
;; candidate-positive-proof
;;   : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows Nat
;;         PositiveProof)
;;   | doc m%
;;       Replay an inspected positive proposal against a copied
;;       snapshot and compare its query rows with a complete native solve.
;;       The work cap bounds body-row probes and scalar clauses; status distinguishes
;;       complete, bounded and unsupported proof generation.
;;
;;       # Examples
;;
;;       ```scheme
;;       (candidate-positive-proof snapshot spec digest 'complete rows 1000)
;;       ;; => a bound proof value, or bounded/unsupported without nodes
;;       ```
;;     %
(def (candidate-positive-proof/option snapshot spec candidate-digest
                                      native-status native-rows max-steps
                                      retain-closed-absence?)
  (unless (and (exact-integer? max-steps) (> max-steps 0))
    (error "invalid positive proof work budget" max-steps))
  (let ((query (vector-ref (reasoning-candidate-query spec) 0)))
    (def (result status nodes roots)
      (make-positive-proof
       status (reasoning-snapshot-identity snapshot)
       (reasoning-snapshot-generation snapshot)
       (reasoning-snapshot-digest snapshot)
       candidate-digest (candidate-copy-pairs query) max-steps nodes roots))
    (if (or (not (reasoning-snapshot-valid? snapshot))
            (not (eq? native-status 'complete))
            (not (positive-rules? spec)))
      (result 'unsupported [] [])
      (let ((index (make-hash-table))
            (nodes [])
            (next-id 0)
            (derived-count 0)
            (steps 0)
            (material (and retain-closed-absence? (make-certificate-material-budget)))
            (bounded? #f)
            (derived-limit (cadr (reasoning-candidate-limits spec))))
        (def (facts name)
          (let (relation (hash-get index name))
            (if relation (proof-relation-nodes relation) [])))
        (def (active?) (not bounded?))
        (def (known? name row)
          (let (relation (hash-get index name))
            (and relation (hash-get (proof-relation-members relation) row))))
        ;; Reserve source and pending rows together, before copying a node.
        ;; Ordinary positive witnesses retain their existing proposal budget.
        (def (reserve-row! row)
          (or (not material) (certificate-material-reserve! material row)
              (begin (set! bounded? #t) #f)))
        (def (install! node)
          (let* ((name (proof-node-relation node))
                 (relation (or (hash-get index name)
                               (let (owned (make-proof-relation [] #f (make-hash-table)))
                                 (hash-put! index name owned) owned)))
                 (cell (list node)))
            (if (proof-relation-tail relation)
              (set-cdr! (proof-relation-tail relation) cell)
              (proof-relation-nodes-set! relation cell))
            (proof-relation-tail-set! relation cell)
            (hash-put! (proof-relation-members relation) (proof-node-row node) node)
            (set! nodes (cons node nodes))))
        (def (add! kind name row label inputs)
          (when (and (not bounded?) (not (known? name row)) (reserve-row! row))
            (let (node (make-proof-node next-id kind name (candidate-copy-pairs row)
                                       label (candidate-copy-pairs inputs)))
              (set! next-id (+ next-id 1))
              (install! node))))
        (certificate-for-each-while active?
         (lambda (entry)
           (let (position 0)
             (certificate-for-each-while active?
              (lambda (row)
                (set! position (+ position 1))
                (add! 'source (car entry) row position []))
              (caddr entry))))
         (reasoning-snapshot-relations snapshot))
        (certificate-for-each-while active?
         (lambda (fact)
           (add! 'candidate (vector-ref fact 0) (vector-ref fact 1)
                 (vector-ref fact 2) []))
         (reasoning-candidate-facts spec))
        (let saturate ()
          (let ((pending []) (pending-count 0) (pending-index #f))
            (certificate-for-each-while active?
             (lambda (rule)
               (let ((head (vector-ref rule 0))
                     (body (vector-ref rule 1))
                     (label (vector-ref rule 2)))
                 (def (walk remaining bindings inputs)
                   (unless bounded?
                     (if (null? remaining)
                       (let* ((name (car head))
                              (row (instantiate-head head bindings)))
                         (unless (or (known? name row)
                                     (let (members (and pending-index (hash-get pending-index name)))
                                       (and members (hash-get members row))))
                           (when (>= (+ derived-count pending-count)
                                     derived-limit)
                             (set! bounded? #t))
                           (when (and (not bounded?) (reserve-row! row))
                             (let* ((node (make-proof-node
                                           (+ next-id pending-count)
                                           'rule name (candidate-copy-pairs row) label
                                           (reverse inputs)))
                                    (members (or (and pending-index (hash-get pending-index name))
                                                 (let (table (make-hash-table))
                                                   (unless pending-index
                                                     (set! pending-index (make-hash-table-eq)))
                                                   (hash-put! pending-index name table) table))))
                               (hash-put! members (proof-node-row node) node)
                               (set! pending (cons node pending))
                               (set! pending-count (+ pending-count 1))))))
                       (let (clause (car remaining))
                         (if (positive-fixed-clause? clause)
                           (begin
                             (set! steps (+ steps 1))
                             (if (> steps max-steps)
                               (set! bounded? #t)
                               (let (next (candidate-fixed-clause
                                           clause bindings))
                                 (when next
                                   (walk (cdr remaining) next inputs)))))
                           (certificate-for-each-while active?
                            (lambda (node)
                              (unless bounded?
                                (set! steps (+ steps 1))
                                (if (> steps max-steps)
                                  (set! bounded? #t)
                                  (let (next
                                        (candidate-bind-atom
                                         clause (proof-node-row node)
                                         bindings))
                                    (when next
                                      (walk (cdr remaining) next
                                            (cons (proof-node-id node)
                                                  inputs)))))))
                            (facts (car clause))))))))
                 (walk body [] [])))
             (reasoning-candidate-rules spec))
            (if bounded?
              (result 'bounded [] [])
              (if (null? pending)
                (let* ((matching
                        (filter
                         (lambda (node)
                           (candidate-bind-atom query (proof-node-row node) []))
                         (facts (car query))))
                       (rows (map proof-node-row matching))
                       (roots (map proof-node-id matching)))
                  (cond
                   ((and (pair? roots)
                         (candidate-same-row-set? rows native-rows))
                    (result 'complete (reverse nodes) roots))
                   ((and retain-closed-absence?
                         (null? roots)
                         (null? native-rows))
                    (result 'closed-absent (reverse nodes) []))
                   (else (result 'unsupported [] []))))
                (begin
                  ;; Assign stable IDs in production order; every dependency
                  ;; came from an earlier completed round.
                  (for-each install! (reverse pending))
                  (set! next-id (+ next-id pending-count))
                  (set! derived-count (+ derived-count pending-count))
                  (saturate))))))))))

(def (candidate-positive-proof snapshot spec candidate-digest
                               native-status native-rows max-steps)
  (candidate-positive-proof/option
   snapshot spec candidate-digest native-status native-rows
   max-steps #f))

;;; Internal closure witness for the finite positive nonmembership module.
;;; Its nodes are a candidate post-fixed relation set, not a Why proof.
(def (candidate-positive-closed-absence snapshot spec candidate-digest
                                       native-status native-rows max-steps)
  (candidate-positive-proof/option
   snapshot spec candidate-digest native-status native-rows
   max-steps #t))

;;; Compile private replay metadata lookup by admitted collection shape.
;;; Empty/singleton collections need no table. General labels retain the
;;; first entry, matching assq/find without choosing order through a hash.
;; : (-> MetadataEntries (-> MetadataKey (Maybe Metadata)))
(def (proof-metadata-lookup entries)
  (match entries
    ([] (lambda (_) #f))
    ([entry] (lambda (key) (and (equal? key (car entry)) (cdr entry))))
    (else
     (let (index (make-hash-table))
       (for-each (lambda (entry)
                   (unless (hash-get index (car entry))
                     (hash-put! index (car entry) (cdr entry)))) entries)
       (lambda (key) (hash-get index key))))))

;;; Recheck an externally held proof without trusting its rule nodes.
;;; This checks one derivation per native row, not provenance completeness
;;; or absence. The caller still authenticates snapshot and program digests.
;; candidate-verify-positive-proof
;;   : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows
;;         PositiveProof Nat Boolean)
;;   | doc m%
;;       Replay every node against the inspected source and rule clauses,
;;       then match the query roots to the complete native rows.
;;
;;       # Examples
;;
;;       ```scheme
;;       (candidate-verify-positive-proof
;;         snapshot spec digest 'complete rows proof 64)
;;       ;; => #t only for a locally consistent bounded proof DAG
;;       ```
;;     %
(def (candidate-verify-positive-proof snapshot spec candidate-digest
                                      native-status native-rows proof
                                      max-nodes)
  (and (positive-proof? proof)
       (reasoning-snapshot-valid? snapshot)
       (eq? (positive-proof-status proof) 'complete)
       (eq? native-status 'complete)
       (positive-rules? spec)
       (exact-integer? max-nodes) (> max-nodes 0)
       (equal? (positive-proof-snapshot-identity proof)
               (reasoning-snapshot-identity snapshot))
       (equal? (positive-proof-snapshot-generation proof)
               (reasoning-snapshot-generation snapshot))
       (equal? (positive-proof-snapshot-digest proof)
               (reasoning-snapshot-digest snapshot))
       (equal? (positive-proof-candidate-digest proof) candidate-digest)
       (equal? (positive-proof-query proof)
               (vector-ref (reasoning-candidate-query spec) 0))
       (let* ((nodes (positive-proof-nodes proof))
              (node-count (bounded-list-length nodes max-nodes)))
         ;; Reject the external spines before allocating the node index. Roots
         ;; emitted by the generator contain at most one entry per proof node.
         (and node-count
              (bounded-list-length (positive-proof-roots proof) node-count)
              (let* ((by-id (list->vector nodes))
                     (arities (proof-metadata-lookup (candidate-schema-of snapshot spec)))
                     (source (reasoning-snapshot-relations snapshot))
                     (facts (reasoning-candidate-facts spec))
                     (rules (reasoning-candidate-rules spec))
                     (query (positive-proof-query proof))
                     (source-rows (proof-metadata-lookup
                                   (map (lambda (entry) (cons (car entry) (list->vector (caddr entry)))) source)))
                     (fact-keys (and (pair? facts) (make-hash-table)))
                     (rule-labels (proof-metadata-lookup
                                   (map (lambda (rule)
                                          (cons (vector-ref rule 2)
                                            (cons rule (length (filter positive-atom? (vector-ref rule 1)))))) rules))))
                ;; Independent replay owns its lookup tables. Source vectors retain
                ;; duplicate occurrence positions; label lookup retains find's first
                ;; rule even when supplied labels repeat. No producer index is reused.
                (for-each (lambda (fact)
                            (hash-put! fact-keys
                              (list (vector-ref fact 2) (vector-ref fact 0) (vector-ref fact 1)) #t)) facts)
                (def (existing-input? id before)
                  (and (exact-integer? id) (<= 0 id) (< id before)))
                (def (node-valid? node index)
                  (and (proof-node? node)
                       (exact-integer? (proof-node-id node))
                       (= (proof-node-id node) index)
                       (symbol? (proof-node-relation node))
                       (let (arity (arities (proof-node-relation node)))
                         (and arity
                              (equal? (bounded-list-length (proof-node-row node) arity) arity)))
                       (case (proof-node-kind node)
                         ((source)
                          (and (null? (proof-node-inputs node))
                               (let (rows
                                     (source-rows (proof-node-relation node)))
                                 (and rows
                                      (exact-integer? (proof-node-label node))
                                      (<= 1 (proof-node-label node))
                                      (<= (proof-node-label node)
                                          (vector-length rows))
                                      (equal? (proof-node-row node)
                                              (vector-ref rows
                                               (- (proof-node-label node) 1)))))))
                         ((candidate)
                          (and (null? (proof-node-inputs node))
                               fact-keys
                               (hash-get fact-keys
                                 (list (proof-node-label node) (proof-node-relation node)
                                       (proof-node-row node)))))
                         ((rule)
                          (let* ((entry (rule-labels (proof-node-label node)))
                                 (rule (and entry (car entry))))
                            (and rule
                                 (eq? (proof-node-relation node)
                                      (car (vector-ref rule 0)))
                                 (equal? (bounded-list-length (proof-node-inputs node) (cdr entry))
                                         (cdr entry))
                                 (let loop ((clauses (vector-ref rule 1))
                                            (inputs (proof-node-inputs node))
                                            (bindings []))
                                   (if (null? clauses)
                                     (and (null? inputs)
                                          (equal?
                                           (proof-node-row node)
                                           (instantiate-head
                                            (vector-ref rule 0) bindings)))
                                     (let (clause (car clauses))
                                       (if (positive-fixed-clause? clause)
                                         (let (next
                                               (candidate-fixed-clause
                                                clause bindings))
                                           (and next
                                                (loop (cdr clauses)
                                                      inputs next)))
                                         (let (id (car inputs))
                                           (and (existing-input? id index)
                                                (let (input (vector-ref by-id id))
                                                  (and
                                                   (eq? (proof-node-relation input)
                                                        (car clause))
                                                   (let (next
                                                         (candidate-bind-atom
                                                          clause
                                                          (proof-node-row input)
                                                          bindings))
                                                     (and next
                                                          (loop (cdr clauses)
                                                                (cdr inputs)
                                                                next))))))))))))))
                         (else #f))))
                (and
                 (let loop ((remaining nodes) (index 0))
                   (or (null? remaining)
                       (and (node-valid? (car remaining) index)
                            (loop (cdr remaining) (+ index 1)))))
                 (andmap
                  (lambda (id)
                    (and (existing-input? id node-count)
                         (eq? (proof-node-relation (vector-ref by-id id))
                              (car query))
                         (candidate-bind-atom
                          query (proof-node-row (vector-ref by-id id)) [])))
                  (positive-proof-roots proof))
                 (candidate-same-row-set?
                  (map (lambda (id)
                         (proof-node-row (vector-ref by-id id)))
                       (positive-proof-roots proof))
                  native-rows)))))))
