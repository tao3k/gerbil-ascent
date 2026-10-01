;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Build one founded proof from a verified finite candidate closure. Search
;;; order is stratum then rule/fact order; the separate checker remains the
;;; authority for the returned proof. This is not a Why-Not producer.
(import (only-in :gerbil-ascent/candidate/types
                 reasoning-snapshot-relations
                 reasoning-candidate-relations reasoning-candidate-facts
                 reasoning-candidate-rules reasoning-candidate-query)
        (only-in :gerbil-ascent/candidate/program candidate-variable?)
        (only-in :gerbil-ascent/candidate/finite-evidence
                 candidate-verified-finite-closure)
        (only-in :gerbil-ascent/candidate/stratified-proof
                 candidate-verify-stratified-proof))

(export candidate-produce-stratified-proof)

(def +maximum-nodes+ 4096)

;; : (forall (a) (-> (PairTree a) (PairTree a)))
;; : (-> Datum Datum)
(def (copy-pairs datum)
  (if (pair? datum)
    (cons (copy-pairs (car datum)) (copy-pairs (cdr datum)))
    datum))

;; : (forall (a) (-> (Atom a) (Row a) (Bindings a)
;;                    (Maybe (Bindings a))))
;; : (-> Atom Row Bindings (Maybe Bindings))
(def (bind-atom atom row prior)
  (let loop ((terms (cdr atom)) (values row) (bindings prior))
    (if (null? terms)
      bindings
      (let ((term (car terms)) (value (car values)))
        (cond
         ((eq? term '?_) (loop (cdr terms) (cdr values) bindings))
         ((candidate-variable? term)
          (let (old (assq term bindings))
            (if old
              (and (equal? (cdr old) value)
                   (loop (cdr terms) (cdr values) bindings))
              (loop (cdr terms) (cdr values)
                    (cons (cons term value) bindings)))))
         (else
          (and (equal? term value)
               (loop (cdr terms) (cdr values) bindings))))))))

;; : (forall (v) (-> Symbol (List (Pair Symbol v)) v))
;; : (-> Symbol SymbolIndex EntryValue)
(def (required-value name bindings)
  (let (entry (assq name bindings))
    (if entry (cdr entry)
      (error "stratified producer is missing inspected entry" name))))

;; : (-> FixedClause Bindings (Maybe Bindings))
(def (fixed-clause clause bindings)
  (let* ((mode (car clause))
         (form (if (eq? mode 'where) (cadr clause) (caddr clause)))
         (inputs (map (lambda (name) (assq name bindings)) (cdr form))))
    (and (andmap (lambda (input) (and input #t)) inputs)
         (let (values (map cdr inputs))
           (case mode
             ((where)
              (case (car form)
                ((even?) (and (exact-integer? (car values))
                              (even? (car values)) bindings))
                ((<) (and (andmap exact-integer? values)
                          (< (car values) (cadr values)) bindings))
                (else #f)))
             ((compute)
              (and (not (assq (cadr clause) bindings))
                   (case (car form)
                     ((identity)
                      (cons (cons (cadr clause) (car values)) bindings))
                     ((+)
                      (and (andmap exact-integer? values)
                           (cons (cons (cadr clause)
                                       (+ (car values) (cadr values)))
                                 bindings)))
                     (else #f))))
             (else #f))))))

;;; Positive reads may stay in a stratum; absence and complete groups must
;;; read a strictly lower stratum. A strict cycle has no founded proof.
;; : (forall (r) (-> (Schema r) (Rules r) (Maybe (Strata r))))
;; : (-> Schema Rules (Maybe Strata))
(def (strata-of schema rules)
  (let ((levels (map (lambda (entry) (cons (car entry) 0)) schema))
        (changed? #f))
    (let loop ((round 0))
      (set! changed? #f)
      (for-each
       (lambda (rule)
         (let (head (car (vector-ref rule 0)))
           (for-each
            (lambda (clause)
              (let (dependency
                    (case (car clause)
                      ((not) (cons (caadr clause) 1))
                      ((reduce) (cons (car (cadddr clause)) 1))
                      ((where compute) #f)
                      (else (cons (car clause) 0))))
                (when dependency
                  (let* ((head-entry (assq head levels))
                         (dep-entry (assq (car dependency) levels))
                         (required (+ (cdr dep-entry) (cdr dependency))))
                    (when (< (cdr head-entry) required)
                      (set-cdr! head-entry required)
                      (set! changed? #t))))))
            (vector-ref rule 1))))
       rules)
      (cond
       ((not changed?) levels)
       ((>= round (length schema)) #f)
       (else (loop (+ round 1)))))))

;;; Return (values complete Proof), (values bounded ()), or an explicit
;;; unsupported/invalid verdict. The checker independently replays the finite
;;; model and checks every node before this producer claims completion.
;; candidate-produce-stratified-proof
;;   : (forall (row) (-> (Snapshot row) (Candidate row) Digest Status
;;                       (Rows row) FiniteEvidence Nat Nat
;;                       (Values Status (Proof row))))
;;   : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows
;;          FiniteEvidence Nat Nat (Values Status ProofDatum))
;;   | doc m%
;;       Produce a bounded founded derivation for every nonempty native query
;;       row. Source, hypothetical fact and rule nodes are ordered so each
;;       positive or reduction dependency points backward. An empty query
;;       and general Why-Not remain unsupported.
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
        (let* ((schema
                (append
                 (map (lambda (entry) (cons (car entry) (cadr entry)))
                      (reasoning-snapshot-relations snapshot))
                 (reasoning-candidate-relations spec)))
               (rules (reasoning-candidate-rules spec))
               (levels (strata-of schema rules))
               (nodes (make-vector +maximum-nodes+ #f))
               (by-row (make-hash-table))
               (by-relation
                (map (lambda (entry) (cons (car entry) [])) schema))
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
            (required-value name levels))
          (def (node-id name row)
            (hash-get by-row (cons name row)))
          (def (add-node! kind name row label witnesses)
            (when (and (not bounded?)
                       (not (node-id name row))
                       (member row (rows name)))
              (if (>= node-count +maximum-nodes+)
                (set! bounded? #t)
                (let ((id node-count)
                      (copy (copy-pairs row)))
                  (vector-set! nodes id
                    (list kind name copy label witnesses))
                  (hash-put! by-row (cons name copy) id)
                  (let (entry (assq name by-relation))
                    (set-cdr! entry (cons id (cdr entry))))
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
                     (let (next (bind-atom atom row bindings))
                       (when next
                         (let (id (node-id name row))
                           (if (not id)
                             (set! ready? #f)
                             (begin
                               (set! ids (cons id ids))
                               (unless (eq? (car operator) 'count)
                                 (set! values
                                   (cons (required-value
                                          (cadr operator) next)
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
                                   (required-value term bindings) term))
                               (cdr head)))
                      (when (step!)
                        (add-node! 'rule head-name row label
                                   (reverse evidence))))
                    (let (clause (car clauses))
                      (case (car clause)
                        ((where compute)
                         (when (step!)
                           (let (next (fixed-clause clause bindings))
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
                                  (when (bind-atom atom row bindings)
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
                                      (bind-atom clause (caddr node)
                                                 bindings)))
                                (when next
                                  (walk (cdr clauses) next
                                        (cons (list 'atom id) evidence))))))
                          (cdr (assq (car clause) by-relation)))))))))
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
