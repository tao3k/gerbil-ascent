;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Build one founded proof from a verified finite candidate closure. Search
;;; order is stratum then rule/fact order; the separate checker remains the
;;; authority for the returned proof. This is not a Why-Not producer.
(import (only-in :gerbil-ascent/candidate/datum candidate-copy-pairs)
        (only-in :std/hash/misc hash-ensure-modify!)
        (only-in :gerbil-ascent/candidate/types
                 reasoning-snapshot-relations
                 reasoning-candidate-relations reasoning-candidate-facts
                 reasoning-candidate-rules reasoning-candidate-query)
        (only-in :gerbil-ascent/candidate/program candidate-variable?)
        (only-in :gerbil-ascent/candidate/funs
                 candidate-schema-of
                 candidate-required-entry candidate-bind-atom
                 candidate-fixed-clause candidate-strata-of)
        (only-in :gerbil-ascent/candidate/finite-evidence
                 candidate-verified-finite-closure)
        (only-in :gerbil-ascent/t/performance/stratified-model/reference-proof
                 candidate-verify-stratified-proof))

(export candidate-produce-stratified-proof)

(def +maximum-nodes+ 4096)

;;; Return (values complete Proof), (values bounded ()), or an explicit
;;; unsupported/invalid verdict. The checker independently replays the finite
;;; model and checks every node before this producer claims completion.
;; candidate-produce-stratified-proof
;;   : (forall (row) (-> (Snapshot row) (Candidate row) Digest Status (Rows row) FiniteEvidence Nat Nat (Values Status (Proof row))))
;;   : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows FiniteEvidence Nat Nat (Values Status ProofDatum))
;;   | doc m%
;;       Produce a bounded founded derivation for every nonempty native query
;;       row. Source, hypothetical fact and rule nodes are ordered so each
;;       positive or reduction dependency points backward. An empty query
;;       and general Why-Not remain unsupported.
;;
;;       # Examples
;;
;;       ```scheme
;;       (candidate-produce-stratified-proof
;;         snapshot spec digest 'complete rows finite-certificate 5000 5000)
;;       ;; => (values 'complete proof) when every row has a founded derivation
;;       ```
;;     %
(def (candidate-produce-stratified-proof snapshot spec candidate-digest
                                         native-status native-rows certificate
                                         finite-work-budget proof-work-budget)
  (unless (and (exact-integer? proof-work-budget) (> proof-work-budget 0))
    (error "stratified producer needs positive work budget"
           proof-work-budget))
  (let-values (((finite-verdict closure)
                (candidate-verified-finite-closure
                 snapshot spec candidate-digest native-status native-rows
                 certificate finite-work-budget)))
    (if (not (eq? finite-verdict 'valid))
      (values finite-verdict [])
      (if (null? native-rows)
        (values 'unsupported [])
        (let* ((schema (candidate-schema-of snapshot spec))
               (rules (reasoning-candidate-rules spec))
               (levels (candidate-strata-of schema rules))
               (nodes (make-vector +maximum-nodes+ #f))
               (by-row (make-hash-table))
               (by-relation (make-hash-table-eq))
               (node-count 0)
               (steps 0)
               (bounded? #f)
               (added? #f))
          (def (step!)
            (set! steps (+ steps 1))
            (when (> steps proof-work-budget) (set! bounded? #t))
            (not bounded?))
          (def (rows name)
            (caddr (assq name closure)))
          (def (level name)
            (cdr (candidate-required-entry name levels)))
          (def (node-id name row)
            (hash-get by-row (cons name row)))
          (def (add-node! kind name row label witnesses)
            (when (and (not bounded?)
                       (not (node-id name row))
                       (member row (rows name)))
              (if (>= node-count +maximum-nodes+)
                (set! bounded? #t)
                (let ((id node-count)
                      (copy (candidate-copy-pairs row)))
                  (vector-set! nodes id
                    (list kind name copy label witnesses))
                  (hash-put! by-row (cons name copy) id)
                  (hash-ensure-modify!
                   by-relation name (lambda () [])
                   (lambda (ids) (cons id ids)))
                  (set! node-count (+ node-count 1))
                  (set! added? #t)))))
          (def (reduction clause bindings head)
            (let* ((output (cadr clause))
                   (operator (caddr clause))
                   (atom (cadddr clause))
                   (name (car atom))
                   (ids [])
                   (values [])
                   (ready? (> (level head) (level name))))
              (when ready?
                (for-each
                 (lambda (row)
                   (when (step!)
                     (let (next (candidate-bind-atom atom row bindings))
                       (when next
                         (let (id (node-id name row))
                           (if (not id)
                             (set! ready? #f)
                             (begin
                               (set! ids (cons id ids))
                               (unless (eq? (car operator) 'count)
                                 (set! values
                                   (cons (cdr (candidate-required-entry
                                               (cadr operator) next))
                                         values))))))))))
                 (rows name)))
              (and (not bounded?) ready?
                   (let (value
                         (case (car operator)
                           ((count) (length ids))
                           ((sum) (and (andmap exact-integer? values)
                                       (apply + 0 values)))
                           ((min) (and (pair? values)
                                       (andmap exact-integer? values)
                                       (apply min values)))
                           ((max) (and (pair? values)
                                       (andmap exact-integer? values)
                                       (apply max values)))
                           (else #f)))
                     (and value
                          (cons (cons (cons output value) bindings)
                                (list 'reduce (reverse ids))))))))
          (def (evaluate-rule rule)
            (let* ((head (vector-ref rule 0))
                   (head-name (car head))
                   (body (vector-ref rule 1))
                   (label (vector-ref rule 2)))
              (def (walk clauses bindings evidence)
                (unless bounded?
                  (if (null? clauses)
                    (let (row
                          (map (lambda (term)
                                 (if (candidate-variable? term)
                                   (cdr (candidate-required-entry
                                         term bindings)) term))
                               (cdr head)))
                      (when (step!)
                        (add-node! 'rule head-name row label
                                   (reverse evidence))))
                    (let (clause (car clauses))
                      (case (car clause)
                        ((where compute)
                         (when (step!)
                           (let (next (candidate-fixed-clause clause bindings))
                             (when next
                               (walk (cdr clauses) next
                                     (cons '(fixed) evidence))))))
                        ((not)
                         (let* ((atom (cadr clause))
                                (name (car atom))
                                (absent? (> (level head-name)
                                            (level name))))
                           (when absent?
                             (for-each
                              (lambda (row)
                                (when (step!)
                                  (when (candidate-bind-atom atom row bindings)
                                    (set! absent? #f))))
                              (rows name)))
                           (when (and (not bounded?) absent?)
                             (walk (cdr clauses) bindings
                                   (cons '(not) evidence)))))
                        ((reduce)
                         (let (result
                               (reduction clause bindings head-name))
                           (when result
                             (walk (cdr clauses) (car result)
                                   (cons (cdr result) evidence)))))
                        (else
                         (for-each
                          (lambda (id)
                            (when (step!)
                              (let* ((node (vector-ref nodes id))
                                     (next
                                      (candidate-bind-atom clause (caddr node)
                                                           bindings)))
                                (when next
                                  (walk (cdr clauses) next
                                        (cons (list 'atom id) evidence))))))
                          (or (hash-get by-relation (car clause)) []))))))))
              (walk body [] [])))
          (if (not levels)
            (values 'invalid [])
            (begin
              (for-each
               (lambda (entry)
                 (let ((name (car entry)) (position 0))
                   (for-each
                    (lambda (row)
                      (set! position (+ position 1))
                      (when (step!)
                        (add-node! 'source name row position [])))
                    (caddr entry))))
               (reasoning-snapshot-relations snapshot))
              (for-each
               (lambda (fact)
                 (when (step!)
                   (add-node! 'candidate
                              (vector-ref fact 0) (vector-ref fact 1)
                              (vector-ref fact 2) [])))
               (reasoning-candidate-facts spec))
              (let stratum ((current 0)
                            (maximum (apply max (map cdr levels))))
                (when (and (<= current maximum) (not bounded?))
                  (let repeat ()
                    (set! added? #f)
                    (for-each
                     (lambda (rule)
                       (when (and (not bounded?)
                                  (= (level (car (vector-ref rule 0)))
                                     current))
                         (evaluate-rule rule)))
                     rules)
                    (when (and added? (not bounded?)) (repeat)))
                  (stratum (+ current 1) maximum)))
              (if bounded?
                (values 'bounded [])
                (let* ((query
                        (vector-ref (reasoning-candidate-query spec) 0))
                       (roots
                        (map (lambda (row)
                               (node-id (car query) row))
                             native-rows)))
                  (if (not (andmap (lambda (id) (and id #t)) roots))
                    (values 'unsupported [])
                    (let* ((ordered
                            (let loop ((index (- node-count 1)) (result []))
                              (if (< index 0) result
                                (loop (- index 1)
                                      (cons (vector-ref nodes index)
                                            result)))))
                           (proof
                            (list 'stratified-proof-v1 ordered roots))
                           (verdict
                            (candidate-verify-stratified-proof
                             snapshot spec candidate-digest native-status
                             native-rows certificate finite-work-budget
                             proof proof-work-budget)))
                      (case verdict
                        ((valid) (values 'complete proof))
                        ((bounded) (values 'bounded []))
                        (else (values 'invalid []))))))))))))))
