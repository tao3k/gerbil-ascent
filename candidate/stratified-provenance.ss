;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil-ascent/candidate/types
                 reasoning-snapshot-identity reasoning-snapshot-generation reasoning-snapshot-digest
                 reasoning-snapshot-content-digest reasoning-snapshot-relations reasoning-bounded-data?
                 reasoning-candidate-relations reasoning-candidate-facts reasoning-candidate-rules
                 reasoning-candidate-query reasoning-candidate-limits)
        (only-in :gerbil-ascent/candidate/program candidate-variable?)
        (only-in :gerbil-ascent/candidate/funs candidate-copy-pairs candidate-bind-atom
                 candidate-fixed-clause candidate-required-entry)
        (only-in :gerbil-ascent/candidate/finite-evidence candidate-verified-finite-closure))
(export candidate-stratified-provenance candidate-verify-stratified-provenance
        stratified-provenance? stratified-provenance-status stratified-provenance-nodes
        stratified-provenance-edges stratified-provenance-roots)

;;; Finite recursive equations, with exact completed lower-stratum observations.
;;; This represents all grounded alternatives, rather than one founded tree.
(defstruct stratified-provenance (status stamp nodes edges roots))
;;; Boundary: bind graph identity to the complete source and candidate input.
;; : (forall (s p d) (-> s p d Digest))
;; : (-> ReasoningSnapshot CandidateSpec Digest Digest)
(def (graph-stamp snapshot spec digest)
  (reasoning-snapshot-content-digest 'stratified-provenance 0
   (list (reasoning-snapshot-identity snapshot) (reasoning-snapshot-generation snapshot)
         (reasoning-snapshot-digest snapshot) digest
         (reasoning-candidate-relations spec) (reasoning-candidate-facts spec)
         (reasoning-candidate-rules spec) (reasoning-candidate-query spec)
         (reasoning-candidate-limits spec))))
;;; Grounding requires every named variable to have a verified binding.
;; : (forall (v) (-> [v] [(Pair Symbol v)] [v]))
;; : (-> CandidateTerms Bindings GroundTerms)
(def (ground-terms terms bindings)
  (map (lambda (term)
         (if (and (candidate-variable? term) (not (eq? term '?_)))
             (cdr (candidate-required-entry term bindings)) term)) terms))

;; candidate-stratified-provenance
;; : (forall (s p d n r c g) (-> s p d n r c Nat Nat Nat g))
;; : (-> ReasoningSnapshot CandidateSpec Digest Symbol Rows Certificate
;;        Nat Nat Nat StratifiedProvenance)
;; | doc m%
;;     Enumerate bounded grounded alternatives only after independently
;;     verifying the finite closure. Lower-stratum observations are complete.
;;
;;     # Examples
;;
;;     ```scheme
;;     (candidate-stratified-provenance snapshot spec digest status rows
;;                                      certificate 1000 1000 1000)
;;     ;; => a complete graph or a bounded/invalid status without a graph
;;     ```
;;   %
;;; Boundary: verification precedes graph publication; exhaustion publishes no partial graph.
(def (candidate-stratified-provenance snapshot spec digest native-status native-rows certificate
                                     finite-budget graph-budget edge-limit)
  (unless (and (exact-integer? graph-budget) (> graph-budget 0)
               (exact-integer? edge-limit) (> edge-limit 0) (<= edge-limit 65536))
    (error "stratified graph needs bounded positive budgets"))
  (let-values (((verdict closure) (candidate-verified-finite-closure
                                 snapshot spec digest native-status native-rows certificate finite-budget)))
    (if (not (eq? verdict 'valid))
        (make-stratified-provenance verdict #f [] [] [])
        (let ((nodes []) (by-row (make-hash-table)) (by-relation (make-hash-table-eq))
              (edges []) (roots []) (steps 0) (node-count 0) (edge-count 0) (bounded? #f))
          (def (step!)
            (set! steps (+ steps 1))
            (when (> steps graph-budget) (set! bounded? #t)) (not bounded?))
          (def (node-id name row)
            (let (id (hash-get by-row (cons name row)))
              (unless id (error "verified closure missing grounded graph node" name row)) id))
          (def (relation-nodes name) (or (hash-get by-relation name) []))
          (def (add-edge! output kind label witnesses)
            (when (and (not bounded?) (step!))
              (let (edge (list output kind label (candidate-copy-pairs witnesses)))
                (unless (member edge edges)
                  (if (>= edge-count edge-limit) (set! bounded? #t)
                      (begin (set! edge-count (+ edge-count 1)) (set! edges (cons edge edges))))))))
          (for-each (lambda (entry)
            (let (ids [])
              (for-each (lambda (row)
                (when (step!)
                  (if (>= node-count 4096) (set! bounded? #t)
                      (let* ((id node-count) (copy (candidate-copy-pairs row))
                             (node (list id (car entry) copy)))
                        (set! nodes (cons node nodes))
                        (hash-put! by-row (cons (car entry) copy) id)
                        (set! ids (cons node ids)) (set! node-count (+ node-count 1)))))) (caddr entry))
              (hash-put! by-relation (car entry) (reverse ids)))) closure)
          (unless bounded?
            (for-each (lambda (entry)
              (for-each (lambda (row position)
                (add-edge! (node-id (car entry) row) 'source (list (car entry) position) []))
                (caddr entry) (iota (length (caddr entry)) 1))) (reasoning-snapshot-relations snapshot))
            (for-each (lambda (fact)
              (add-edge! (node-id (vector-ref fact 0) (vector-ref fact 1))
                         'candidate (vector-ref fact 2) [])) (reasoning-candidate-facts spec))
            (for-each (lambda (rule position)
              (def (walk clauses bindings witnesses)
                (when (and (not bounded?) (step!))
                  (if (null? clauses)
                      (let* ((head (vector-ref rule 0))
                             (row (ground-terms (cdr head) bindings)))
                        (add-edge! (node-id (car head) row) 'rule
                                   (list position (vector-ref rule 2)) (reverse witnesses)))
                      (let (clause (car clauses))
                        (case (car clause)
                          ((where compute)
                           (let (next (candidate-fixed-clause clause bindings))
                             (when next (walk (cdr clauses) next (cons '(fixed) witnesses)))))
                          ((not)
                           (let* ((atom (cadr clause)) (matches? #f))
                             (for-each (lambda (node)
                               (when (step!)
                                 (when (candidate-bind-atom atom (caddr node) bindings)
                                   (set! matches? #t)))) (relation-nodes (car atom)))
                             (unless (or bounded? matches?)
                               (walk (cdr clauses) bindings
                                (cons (list 'not (car atom) (ground-terms (cdr atom) bindings)) witnesses)))))
                          ((reduce)
                           (let* ((atom (cadddr clause)) (operator (caddr clause)) (ids []) (values []))
                             (for-each (lambda (node)
                               (when (step!)
                                 (let (next (candidate-bind-atom atom (caddr node) bindings))
                                   (when next
                                     (set! ids (cons (car node) ids))
                                     (unless (eq? (car operator) 'count)
                                       (set! values (cons (cdr (candidate-required-entry (cadr operator) next)) values)))))))
                               (relation-nodes (car atom)))
                             (unless bounded?
                               (let (value (case (car operator)
                                             ((count) (length ids))
                                             ((sum) (and (andmap exact-integer? values) (apply + 0 values)))
                                             ((min) (and (pair? values) (andmap exact-integer? values) (apply min values)))
                                             ((max) (and (pair? values) (andmap exact-integer? values) (apply max values)))
                                             (else #f)))
                                 (when value
                                   (walk (cdr clauses) (cons (cons (cadr clause) value) bindings)
                                         (cons (list 'reduce (reverse ids)) witnesses)))))))
                          (else
                           (for-each (lambda (node)
                             (when (step!)
                               (let (next (candidate-bind-atom clause (caddr node) bindings))
                                 (when next (walk (cdr clauses) next (cons (list 'atom (car node)) witnesses))))))
                             (relation-nodes (car clause)))))))))
              (walk (vector-ref rule 1) [] []))
              (reasoning-candidate-rules spec) (iota (length (reasoning-candidate-rules spec)) 1))
            (let (query (vector-ref (reasoning-candidate-query spec) 0))
              (for-each (lambda (node)
                (when (and (step!) (candidate-bind-atom query (caddr node) []))
                  (set! roots (cons (car node) roots)))) (relation-nodes (car query)))))
          (let* ((published-nodes (reverse nodes)) (published-edges (reverse edges)) (published-roots (reverse roots))
                 (datum (list published-nodes published-edges published-roots)))
            (if (or bounded? (not (reasoning-bounded-data? datum 131072 128)))
                (make-stratified-provenance 'bounded #f [] [] [])
                (make-stratified-provenance 'complete (graph-stamp snapshot spec digest)
                                           published-nodes published-edges published-roots)))))))

;; candidate-verify-stratified-provenance
;; : (forall (s p d n r c g) (-> s p d n r c Nat g Nat Nat Symbol))
;; : (-> ReasoningSnapshot CandidateSpec Digest Symbol Rows Certificate
;;        Nat StratifiedProvenance Nat Nat Symbol)
;; | doc m%
;;     Rebuild the bounded graph from verified inputs and compare its stamp,
;;     nodes, edges and roots before accepting an externally supplied graph.
;;
;;     # Examples
;;
;;     ```scheme
;;     (candidate-verify-stratified-provenance snapshot spec digest status rows
;;                                            certificate 1000 graph 1000 1000)
;;     ;; => valid only when the complete graph equals the independent rebuild
;;     ```
;;   %
(def (candidate-verify-stratified-provenance snapshot spec digest native-status native-rows certificate
                                            finite-budget graph graph-budget edge-limit)
  (if (not (and (stratified-provenance? graph) (eq? (stratified-provenance-status graph) 'complete)
                (reasoning-bounded-data? (list (stratified-provenance-nodes graph)
                                              (stratified-provenance-edges graph)
                                              (stratified-provenance-roots graph)) 131072 128)))
      'invalid
      (let (expected (candidate-stratified-provenance snapshot spec digest native-status native-rows certificate
                                                    finite-budget graph-budget edge-limit))
        (if (not (eq? (stratified-provenance-status expected) 'complete))
            (stratified-provenance-status expected)
            (if (and (equal? (stratified-provenance-stamp graph) (stratified-provenance-stamp expected))
                     (equal? (stratified-provenance-nodes graph) (stratified-provenance-nodes expected))
                     (equal? (stratified-provenance-edges graph) (stratified-provenance-edges expected))
                     (equal? (stratified-provenance-roots graph) (stratified-provenance-roots expected)))
                'valid 'invalid)))))
