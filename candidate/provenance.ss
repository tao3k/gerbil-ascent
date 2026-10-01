;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; A bounded proof interpreter for inspected, positive atom-only proposals.
;;; Its result is checked against the completed native query before use.
;;; Node inputs always refer to earlier nodes, so the list is a finite DAG.
(import (only-in :gerbil-ascent/candidate/types
                 reasoning-snapshot-identity reasoning-snapshot-generation
                 reasoning-snapshot-digest reasoning-snapshot-relations
                 reasoning-candidate-facts reasoning-candidate-rules
                 reasoning-candidate-query reasoning-candidate-limits)
        (only-in :gerbil-ascent/candidate/program candidate-variable?))

(export candidate-positive-proof candidate-verify-positive-proof
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

(def (copy-pairs datum)
  (if (pair? datum)
    (cons (copy-pairs (car datum)) (copy-pairs (cdr datum)))
    datum))

(def (positive-atom? atom)
  (and (pair? atom) (symbol? (car atom))
       (not (memq (car atom) '(not where compute reduce)))))

(def (positive-rules? spec)
  (andmap
   (lambda (rule)
     (andmap positive-atom? (vector-ref rule 1)))
   (reasoning-candidate-rules spec)))

(def (bind-atom atom row prior)
  (let loop ((terms (cdr atom)) (values row) (bindings prior))
    (if (null? terms)
      bindings
      (let ((term (car terms)) (value (car values)))
        (cond
         ((eq? term '?_)
          (loop (cdr terms) (cdr values) bindings))
         ((candidate-variable? term)
          (let (existing (assq term bindings))
            (if existing
              (and (equal? (cdr existing) value)
                   (loop (cdr terms) (cdr values) bindings))
              (loop (cdr terms) (cdr values)
                    (cons (cons term value) bindings)))))
         (else
          (and (equal? term value)
               (loop (cdr terms) (cdr values) bindings))))))))

(def (instantiate-head head bindings)
  (map (lambda (term)
         (if (candidate-variable? term)
           (cdr (assq term bindings))
           term))
       (cdr head)))

(def (same-row-set? left right)
  (and (= (length left) (length right))
       (andmap (lambda (row) (if (member row right) #t #f)) left)
       (andmap (lambda (row) (if (member row left) #t #f)) right)))

;;; max-steps bounds body-row probes, including unsuccessful unifications.
;;; The proposal's derived-fact limit separately bounds the DAG size.
;;; A complete proof is returned only when the native solve completed and
;;; this independent interpreter reproduces every native query row.
;;; No absence claim is made here.
;; candidate-positive-proof
;;   : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows Nat
;;         PositiveProof)
;;   | doc m%
;;       Replay an inspected positive-atom proposal against a copied
;;       snapshot and compare its query rows with a complete native solve.
;;       The work cap bounds body-row probes; result status distinguishes
;;       complete, bounded and unsupported proof generation.
;;
;;       # Examples
;;
;;       ```scheme
;;       (candidate-positive-proof snapshot spec digest 'complete rows 1000)
;;       ;; => a bound proof value, or bounded/unsupported without nodes
;;       ```
;;     %
(def (candidate-positive-proof snapshot spec candidate-digest
                               native-status native-rows max-steps)
  (unless (and (exact-integer? max-steps) (> max-steps 0))
    (error "invalid positive proof work budget" max-steps))
  (let ((query (vector-ref (reasoning-candidate-query spec) 0)))
    (def (result status nodes roots)
      (make-positive-proof
       status (reasoning-snapshot-identity snapshot)
       (reasoning-snapshot-generation snapshot)
       (reasoning-snapshot-digest snapshot)
       candidate-digest (copy-pairs query) max-steps nodes roots))
    (if (or (not (eq? native-status 'complete))
            (not (positive-rules? spec)))
      (result 'unsupported [] [])
      (let ((index (make-hash-table))
            (nodes [])
            (next-id 0)
            (derived-count 0)
            (steps 0)
            (bounded? #f)
            (derived-limit (cadr (reasoning-candidate-limits spec))))
        (def (facts name)
          (or (hash-get index name) []))
        (def (known? name row extra)
          (or (find (lambda (node) (equal? (proof-node-row node) row))
                    (facts name))
              (find (lambda (node)
                      (and (eq? (proof-node-relation node) name)
                           (equal? (proof-node-row node) row)))
                    extra)))
        (def (add! kind name row label inputs)
          (unless (known? name row [])
            (let (node (make-proof-node next-id kind name (copy-pairs row)
                                       label (copy-pairs inputs)))
              (set! next-id (+ next-id 1))
              (hash-put! index name (append (facts name) (list node)))
              (set! nodes (cons node nodes)))))
        (for-each
         (lambda (entry)
           (for-each
            (lambda (row position)
              (add! 'source (car entry) row position []))
            (caddr entry) (iota (length (caddr entry)) 1)))
         (reasoning-snapshot-relations snapshot))
        (for-each
         (lambda (fact)
           (add! 'candidate (vector-ref fact 0) (vector-ref fact 1)
                 (vector-ref fact 2) []))
         (reasoning-candidate-facts spec))
        (let saturate ()
          (let (pending [])
            (for-each
             (lambda (rule)
               (let ((head (vector-ref rule 0))
                     (body (vector-ref rule 1))
                     (label (vector-ref rule 2)))
                 (def (walk remaining bindings inputs)
                   (unless bounded?
                     (if (null? remaining)
                       (let* ((name (car head))
                              (row (instantiate-head head bindings)))
                         (unless (known? name row pending)
                           (when (>= (+ derived-count (length pending))
                                     derived-limit)
                             (set! bounded? #t))
                           (unless bounded?
                             (set! pending
                               (cons (make-proof-node
                                      (+ next-id (length pending))
                                      'rule name (copy-pairs row) label
                                      (reverse inputs))
                                     pending)))))
                       (let (atom (car remaining))
                         (for-each
                          (lambda (node)
                            (unless bounded?
                              (set! steps (+ steps 1))
                              (if (> steps max-steps)
                                (set! bounded? #t)
                                (let (next
                                      (bind-atom atom (proof-node-row node)
                                                 bindings))
                                  (when next
                                    (walk (cdr remaining) next
                                          (cons (proof-node-id node)
                                                inputs)))))))
                          (facts (car atom)))))))
                 (walk body [] [])))
             (reasoning-candidate-rules spec))
            (if bounded?
              (result 'bounded [] [])
              (if (null? pending)
                (let* ((matching
                        (filter
                         (lambda (node)
                           (bind-atom query (proof-node-row node) []))
                         (facts (car query))))
                       (rows (map proof-node-row matching))
                       (roots (map proof-node-id matching)))
                  (if (and (pair? roots)
                           (same-row-set? rows native-rows))
                    (result 'complete (reverse nodes) roots)
                    (result 'unsupported [] [])))
                (begin
                  ;; Assign stable IDs in production order; every dependency
                  ;; came from an earlier completed round.
                  (for-each
                   (lambda (node)
                     (hash-put! index (proof-node-relation node)
                                (append (facts (proof-node-relation node))
                                        (list node)))
                     (set! nodes (cons node nodes)))
                   (reverse pending))
                  (set! next-id (+ next-id (length pending)))
                  (set! derived-count (+ derived-count (length pending)))
                  (saturate))))))))))

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
       (list? (positive-proof-nodes proof))
       (<= (length (positive-proof-nodes proof)) max-nodes)
       (list? (positive-proof-roots proof))
       (let* ((nodes (positive-proof-nodes proof))
              (by-id (list->vector nodes))
              (source (reasoning-snapshot-relations snapshot))
              (facts (reasoning-candidate-facts spec))
              (rules (reasoning-candidate-rules spec))
              (query (positive-proof-query proof)))
         (def (existing-input? id before)
           (and (exact-integer? id) (<= 0 id) (< id before)))
         (def (node-valid? node index)
           (and (proof-node? node)
                (exact-integer? (proof-node-id node))
                (= (proof-node-id node) index)
                (symbol? (proof-node-relation node))
                (list? (proof-node-row node))
                (list? (proof-node-inputs node))
                (case (proof-node-kind node)
                  ((source)
                   (and (null? (proof-node-inputs node))
                        (let (entry
                              (assq (proof-node-relation node) source))
                          (and entry
                               (exact-integer? (proof-node-label node))
                               (<= 1 (proof-node-label node))
                               (<= (proof-node-label node)
                                   (length (caddr entry)))
                               (equal? (proof-node-row node)
                                       (list-ref
                                        (caddr entry)
                                        (- (proof-node-label node) 1)))))))
                  ((candidate)
                   (and (null? (proof-node-inputs node))
                        (find
                         (lambda (fact)
                           (and (equal? (proof-node-label node)
                                        (vector-ref fact 2))
                                (eq? (proof-node-relation node)
                                     (vector-ref fact 0))
                                (equal? (proof-node-row node)
                                        (vector-ref fact 1))))
                         facts)))
                  ((rule)
                   (let (rule
                         (find
                          (lambda (candidate)
                            (equal? (proof-node-label node)
                                    (vector-ref candidate 2)))
                          rules))
                     (and rule
                          (eq? (proof-node-relation node)
                               (car (vector-ref rule 0)))
                          (= (length (proof-node-inputs node))
                             (length (vector-ref rule 1)))
                          (let loop ((atoms (vector-ref rule 1))
                                     (inputs (proof-node-inputs node))
                                     (bindings []))
                            (if (null? atoms)
                              (equal?
                               (proof-node-row node)
                               (instantiate-head
                                (vector-ref rule 0) bindings))
                              (let (id (car inputs))
                                (and (existing-input? id index)
                                     (let (input (vector-ref by-id id))
                                       (and
                                        (eq? (proof-node-relation input)
                                             (caar atoms))
                                        (let (next
                                              (bind-atom
                                               (car atoms)
                                               (proof-node-row input)
                                               bindings))
                                          (and next
                                               (loop (cdr atoms)
                                                     (cdr inputs)
                                                     next))))))))))))
                  (else #f))))
         (and
          (let loop ((remaining nodes) (index 0))
            (or (null? remaining)
                (and (node-valid? (car remaining) index)
                     (loop (cdr remaining) (+ index 1)))))
          (andmap
           (lambda (id)
             (and (existing-input? id (length nodes))
                  (eq? (proof-node-relation (vector-ref by-id id))
                       (car query))
                  (bind-atom
                   query (proof-node-row (vector-ref by-id id)) [])))
           (positive-proof-roots proof))
          (same-row-set?
           (map (lambda (id)
                  (proof-node-row (vector-ref by-id id)))
                (positive-proof-roots proof))
           native-rows)))))
