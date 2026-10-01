;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Check an externally supplied, founded derivation against an exact finite
;;; stratum replay. This is a bounded proof for one inspected candidate, not
;;; provenance completeness or source authentication. The producer is separate.
(import (only-in :gerbil-ascent/candidate/types
                 reasoning-bounded-data? reasoning-snapshot-relations
                 reasoning-candidate-relations
                 reasoning-candidate-facts reasoning-candidate-rules
                 reasoning-candidate-query)
        (only-in :gerbil-ascent/candidate/program candidate-variable? scalar?)
        (only-in :gerbil-ascent/candidate/funs
                 candidate-schema-of candidate-required-entry
                 candidate-bind-atom candidate-fixed-clause
                 candidate-strata-of)
        (only-in :gerbil-ascent/candidate/finite-evidence
                 candidate-verified-finite-closure))

(export candidate-verify-stratified-proof)

(def +max-proof-nodes+ 4096)
(def +max-proof-datum-nodes+ 65536)

;; : (forall (a) (-> (List a) Nat Boolean))
;; : (-> GroundRow Arity Boolean)
(def (ground-row? row arity)
  (and (list? row) (= (length row) arity)
       (andmap (lambda (term)
                 (and (scalar? term) (not (candidate-variable? term))
                      (not (eq? term '?_))))
               row)))

;;; Exact set equality also rejects a repeated group row. Count each row
;;; insertion/probe against the caller's proof-check budget.
;; : (forall (a) (-> (Rows a) (Rows a) (-> Boolean) Boolean))
;; : (-> Rows Rows BudgetStep Boolean)
(def (same-distinct-rows? supplied actual step!)
  (and (= (length supplied) (length actual))
       (let (index (make-hash-table))
         (and
          (andmap (lambda (row)
                    (and (step!)
                         (begin (hash-put! index row #t) #t)))
                  actual)
          (andmap (lambda (row)
                    (and (step!) (hash-get index row)
                         (begin (hash-put! index row #f) #t)))
                  supplied)))))

;;; Data grammar:
;;; (stratified-proof-v1
;;;   ((source relation row source-position ())
;;;    (candidate relation row fact-label ())
;;;    (rule relation row rule-label
;;;      ((atom earlier-node) (not) (fixed) (reduce (earlier-nodes ...)))))
;;;   (root-node-id ...))
;;; Body evidence has one entry per rule clause. Positive and reduction
;;; inputs refer only to earlier nodes; the exact finite closure is used to
;;; check negative absence and the complete reduction group.
;; candidate-verify-stratified-proof
;;   : (forall (row) (-> (Snapshot row) (Candidate row) Digest Status (Rows row) FiniteEvidence Nat Datum Nat Verdict))
;;   : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows FiniteEvidence Nat ProofDatum Nat Verdict)
;;   | doc m%
;;       Check every supplied source, hypothetical fact, rule and query root
;;       against a completed independently replayed finite closure. Strict
;;       lower strata justify negation and exact groups justify reductions.
;;       Returns valid, invalid, bounded or unsupported; valid does not
;;       authenticate the source or prove candidate intent.
;;
;;       # Examples
;;
;;       ```scheme
;;       (candidate-verify-stratified-proof
;;         snapshot spec digest 'complete native-rows finite-cert
;;         5000 proof-datum 5000)
;;       ;; => valid only for a founded, complete bounded derivation
;;       ```
;;     %
(def (candidate-verify-stratified-proof snapshot spec candidate-digest
                                        native-status native-rows finite-certificate
                                        finite-work-budget proof proof-work-budget)
  (unless (and (exact-integer? proof-work-budget) (> proof-work-budget 0))
    (error "stratified proof needs positive work budget" proof-work-budget))
  (if (not (and (reasoning-bounded-data?
                proof +max-proof-datum-nodes+ 128)
                (list? proof) (= (length proof) 3)
                (eq? (car proof) 'stratified-proof-v1)
                (list? (cadr proof))
                (<= (length (cadr proof)) +max-proof-nodes+)
                (list? (caddr proof))
                (<= (length (caddr proof)) +max-proof-nodes+)))
    'invalid
    (let-values (((finite-verdict closure)
                  (candidate-verified-finite-closure
                   snapshot spec candidate-digest native-status native-rows
                   finite-certificate finite-work-budget)))
      (if (not (eq? finite-verdict 'valid))
        finite-verdict
        (if (null? native-rows)
          'unsupported
          (let* ((schema (candidate-schema-of snapshot spec))
                 (rules (reasoning-candidate-rules spec))
                 (levels (candidate-strata-of schema rules))
                 (nodes (cadr proof))
                 (roots (caddr proof))
                 (by-id (list->vector nodes))
                 (query (vector-ref (reasoning-candidate-query spec) 0))
                 (steps 0)
                 (bounded? #f))
            (def (step!)
              (set! steps (+ steps 1))
              (when (> steps proof-work-budget) (set! bounded? #t))
              (not bounded?))
            (def (rows name)
              (caddr (candidate-required-entry name closure)))
            (def (node-ref id before relation)
              (and (exact-integer? id) (<= 0 id) (< id before)
                   (let (node (vector-ref by-id id))
                     (and (eq? (cadr node) relation) node))))
            (def (strict-lower? head dependency)
              (> (cdr (candidate-required-entry head levels))
                 (cdr (candidate-required-entry dependency levels))))
            (def (no-match? atom bindings)
              (andmap (lambda (row)
                        (and (step!)
                             (not (candidate-bind-atom atom row bindings))))
                      (rows (car atom))))
            (def (reduction-bindings clause witness bindings before head)
              (let ((atom (cadddr clause))
                    (operator (caddr clause)))
                (and (list? witness) (= (length witness) 2)
                     (eq? (car witness) 'reduce)
                     (list? (cadr witness))
                     (strict-lower? head (car atom))
                     (let ((matched
                            (filter (lambda (row)
                                      (and (step!)
                                           (candidate-bind-atom atom row bindings)))
                                    (rows (car atom))))
                           (supplied []))
                       (and (not bounded?)
                            (andmap
                             (lambda (id)
                               (let (node (node-ref id before (car atom)))
                                 (and (step!) node
                                      (candidate-bind-atom atom (caddr node) bindings)
                                      (begin
                                        (set! supplied
                                          (cons (caddr node) supplied))
                                        #t))))
                             (cadr witness))
                            (same-distinct-rows?
                             supplied matched step!)
                            (let* ((values
                                    (if (eq? (car operator) 'count)
                                      []
                                      (map
                                       (lambda (row)
                                         (let (next
                                               (candidate-bind-atom atom row bindings))
                                           (and next
                                                (cdr (candidate-required-entry
                                                      (cadr operator) next)))))
                                       supplied)))
                                   (value
                                    (case (car operator)
                                      ((count) (length supplied))
                                      ((sum) (and (andmap exact-integer? values)
                                                  (apply + 0 values)))
                                      ((min) (and (pair? values)
                                                  (andmap exact-integer? values)
                                                  (apply min values)))
                                      ((max) (and (pair? values)
                                                  (andmap exact-integer? values)
                                                  (apply max values)))
                                      (else #f))))
                              (and value
                                   (cons (cons (cadr clause) value)
                                         bindings))))))))
            (def (rule-node-valid? node index)
              (let* ((rule
                      (find (lambda (candidate)
                              (equal? (cadddr node)
                                      (vector-ref candidate 2)))
                            rules))
                     (head (and rule (vector-ref rule 0)))
                     (body (and rule (vector-ref rule 1)))
                     (witnesses (list-ref node 4)))
                (and rule (eq? (cadr node) (car head))
                     (list? witnesses) (= (length witnesses) (length body))
                     (let loop ((clauses body) (evidence witnesses)
                                (bindings []))
                       (if (null? clauses)
                         (and (null? evidence)
                              (andmap (lambda (term)
                                        (or (not (candidate-variable? term))
                                            (assq term bindings)))
                                      (cdr head))
                              (equal?
                               (caddr node)
                               (map (lambda (term)
                                      (if (candidate-variable? term)
                                        (cdr (candidate-required-entry
                                              term bindings)) term))
                                    (cdr head))))
                         (let ((clause (car clauses))
                               (witness (car evidence)))
                           (case (car clause)
                             ((where compute)
                              (and (equal? witness '(fixed))
                                   (step!)
                                   (let (next (candidate-fixed-clause clause bindings))
                                     (and next
                                          (loop (cdr clauses)
                                                (cdr evidence) next)))))
                             ((not)
                              (and (equal? witness '(not))
                                   (strict-lower? (car head)
                                                  (caadr clause))
                                   (no-match? (cadr clause) bindings)
                                   (loop (cdr clauses) (cdr evidence)
                                         bindings)))
                             ((reduce)
                              (let (next
                                    (reduction-bindings
                                     clause witness bindings index
                                     (car head)))
                                (and next
                                     (loop (cdr clauses) (cdr evidence)
                                           next))))
                             (else
                              (and (list? witness)
                                   (= (length witness) 2)
                                   (eq? (car witness) 'atom)
                                   (let (input
                                         (node-ref (cadr witness) index
                                                   (car clause)))
                                     (and (step!) input
                                          (let (next
                                                (candidate-bind-atom
                                                 clause (caddr input)
                                                 bindings))
                                            (and next
                                                 (loop (cdr clauses)
                                                       (cdr evidence)
                                                       next))))))))))))))
            (def (node-valid? node index)
              (and (step!)
                   (list? node) (= (length node) 5)
                   (memq (car node) '(source candidate rule))
                   (symbol? (cadr node))
                   (let (declaration (assq (cadr node) schema))
                     (and declaration
                          (ground-row? (caddr node) (cdr declaration))
                          (member (caddr node) (rows (cadr node)))))
                   (list? (list-ref node 4))
                   (case (car node)
                     ((source)
                      (and (null? (list-ref node 4))
                           (let (entry
                                 (assq (cadr node)
                                       (reasoning-snapshot-relations
                                        snapshot)))
                             (and entry
                                  (exact-integer? (cadddr node))
                                  (<= 1 (cadddr node))
                                  (<= (cadddr node) (length (caddr entry)))
                                  (equal? (caddr node)
                                          (list-ref (caddr entry)
                                                    (- (cadddr node) 1)))))))
                     ((candidate)
                      (and (null? (list-ref node 4))
                           (find (lambda (fact)
                                   (and (equal? (cadddr node)
                                                (vector-ref fact 2))
                                        (eq? (cadr node)
                                             (vector-ref fact 0))
                                        (equal? (caddr node)
                                                (vector-ref fact 1))))
                                 (reasoning-candidate-facts spec))))
                     ((rule) (rule-node-valid? node index))
                     (else #f))))
            (if (not levels)
              'invalid
              (let (valid-nodes?
                    (let loop ((remaining nodes) (index 0))
                      (or (null? remaining)
                          (and (node-valid? (car remaining) index)
                               (loop (cdr remaining) (+ index 1))))))
                (cond
                 (bounded? 'bounded)
                 ((not valid-nodes?) 'invalid)
                 ((not (and (pair? roots)
                            (andmap
                             (lambda (id)
                               (let (node (node-ref id (length nodes)
                                                     (car query)))
                                 (and (step!) node
                                      (candidate-bind-atom query (caddr node) []))))
                             roots)))
                  (if bounded? 'bounded 'invalid))
                 ((same-distinct-rows?
                   (map (lambda (id) (caddr (vector-ref by-id id))) roots)
                   native-rows step!)
                  (if bounded? 'bounded 'valid))
                 (bounded? 'bounded)
                 (else 'invalid))))))))))
