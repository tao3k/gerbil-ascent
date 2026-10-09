;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Exact finite replay for the inspected candidate subset. This is a
;;; snapshot-relative model check, not general recursive provenance.
;;; The replay does not call the ASCENT planner, evaluator or solver.
(import (only-in :gerbil-ascent/candidate/datum candidate-copy-pairs)
        (only-in :gerbil-ascent/candidate/certificate-limits
                 +max-certificate-relations+ +max-certificate-rows+
                 +max-certificate-cells+ +max-certificate-row-arity+
                 bounded-list-length unique-rows? certificate-for-each-while
                 make-certificate-material-budget certificate-material-reserve!)
        (only-in :gerbil-ascent/candidate/program-identity
                 candidate-finite-program-fingerprint)
        (only-in :gerbil-ascent/candidate/types
                 reasoning-snapshot-identity reasoning-snapshot-generation
                 reasoning-snapshot-digest reasoning-snapshot-relations
                 reasoning-snapshot-valid?
                 reasoning-candidate-facts
                 reasoning-candidate-rules reasoning-candidate-query
                 reasoning-candidate-limits)
        (only-in :gerbil-ascent/candidate/program candidate-variable? scalar?)
        (only-in :gerbil-ascent/candidate/funs
                 candidate-same-row-set?
                 candidate-schema-of candidate-required-entry
                 candidate-bind-atom candidate-fixed-clause
                 candidate-strata-of))

(export candidate-finite-evidence candidate-verify-finite-evidence
        candidate-verified-finite-closure
        finite-evidence? finite-evidence-status finite-evidence-closure
        finite-evidence-query finite-evidence-candidate-digest)

(defstruct finite-evidence
  (status snapshot-identity snapshot-generation snapshot-digest
          candidate-digest program query work-budget closure))

;;; Replay owns the row copies, reversed accumulator, membership index and
;;; published frontier. Published spines are never mutated: a rule can retain
;;; its current frontier while another binding inserts a later row.
(defstruct replay-relation (arity reversed present frontier dirty?) final: #t)

;; : (forall (row) (-> (Closure row) Schema Boolean))
;; : (-> CertificateClosure Schema Boolean)
(def (closure-valid? closure schema)
  (and (equal? (bounded-list-length closure
                                    +max-certificate-relations+)
               (length schema))
       (let ((rows 0) (cells 0))
         (andmap
          (lambda (entry declaration)
            (and (equal? (bounded-list-length entry 3) 3)
                 (eq? (car entry) (car declaration))
                 (exact-integer? (cadr entry))
                 (= (cadr entry) (cdr declaration))
                 (let (count
                       (bounded-list-length
                        (caddr entry) (- +max-certificate-rows+ rows)))
                   (and count
                        (begin (set! rows (+ rows count)) #t)))
                 (<= rows +max-certificate-rows+)
                 (unique-rows? (caddr entry))
                 (andmap
                  (lambda (row)
                    (let (width
                          (bounded-list-length
                           row (min +max-certificate-row-arity+
                                    (- +max-certificate-cells+ cells))))
                      (and width (= width (cadr entry))
                           (begin (set! cells (+ cells width))
                                  #t)
                           (andmap scalar? row))))
                  (caddr entry))))
          closure schema))))

;; : (forall (v) (-> (List v) (Bindings v) (Row v)))
;; : (-> Terms Bindings Row)
(def (instantiate terms bindings)
  (map (lambda (term)
         (if (candidate-variable? term)
           (cdr (candidate-required-entry term bindings))
           term))
       terms))

;;; Returns exact relation sets or bounded/unsupported. The input is an
;;; already inspected candidate. Work counts every relation-row probe and
;;; fixed operation, including probes that do not produce a row.
;; : (-> ReasoningSnapshot InspectedCandidate Nat (Values Status Closure))
(def (finite-replay snapshot spec work-budget)
  (let* ((schema (candidate-schema-of snapshot spec))
         (rules (reasoning-candidate-rules spec))
         (levels (candidate-strata-of schema rules))
         (tables
          (map (lambda (entry)
                 (cons (car entry)
                       (make-replay-relation (cdr entry) [] (make-hash-table) [] #f)))
               schema))
         (steps 0)
         (bounded? #f)
         (material (make-certificate-material-budget))
         (derived-count 0)
         (derived-limit (cadr (reasoning-candidate-limits spec))))
        (def (active?) (not bounded?))
        (def (rows name)
          ;; The record is constructed above and stays local to this replay.
          (using (relation (cdr (candidate-required-entry name tables)) :- replay-relation)
            (when relation.dirty?
              (set! relation.frontier (reverse relation.reversed))
              (set! relation.dirty? #f))
            relation.frontier))
        (def (add-row! name row derived?)
          (using (relation (cdr (candidate-required-entry name tables)) :- replay-relation)
            (if (or bounded? (hash-get relation.present row))
              #f
              (begin
                (when derived?
                  (set! derived-count (+ derived-count 1))
                  (when (> derived-count derived-limit)
                    (set! bounded? #t)))
                (unless (or bounded? (certificate-material-reserve! material row))
                  (set! bounded? #t))
                (if bounded?
                  #f
                  (let (owned (candidate-copy-pairs row))
                    (hash-put! relation.present owned #t)
                    (set! relation.reversed (cons owned relation.reversed))
                    (set! relation.dirty? #t)
                    #t))))))
        (def (step!)
          (unless bounded?
            (set! steps (+ steps 1))
            (when (> steps work-budget) (set! bounded? #t)))
          (not bounded?))
        (def (evaluate-rule rule)
          (let ((head (vector-ref rule 0))
                (body (vector-ref rule 1))
                (changed? #f))
            (def (walk clauses bindings)
              (unless bounded?
                (if (null? clauses)
                  (when (add-row! (car head)
                                  (instantiate (cdr head) bindings) #t)
                    (set! changed? #t))
                  (let (clause (car clauses))
                    (case (car clause)
                      ((where compute)
                       (when (step!)
                         (let (next (candidate-fixed-clause clause bindings))
                           (when next (walk (cdr clauses) next)))))
                      ((not)
                       (let* ((atom (cadr clause))
                              (matched? #f))
                         ;; One witness rejects negation. Absence requires the
                         ;; entire frozen relation and its final charged step.
                         (let probe ((remaining (rows (car atom))))
                           (when (and (pair? remaining) (step!))
                             (if (candidate-bind-atom atom (car remaining) bindings)
                               (set! matched? #t)
                               (probe (cdr remaining)))))
                         (when (and (not bounded?) (not matched?)
                                    (step!))
                           (walk (cdr clauses) bindings))))
                      ((reduce)
                       (let* ((output (cadr clause))
                              (operator (caddr clause))
                              (atom (cadddr clause))
                              (mode (car operator))
                              (accumulator (and (memq mode '(count sum)) 0))
                              (numeric? #t))
                         (let probe ((remaining (rows (car atom))))
                           (when (and (pair? remaining) (step!))
                              (let (next (candidate-bind-atom atom (car remaining) bindings))
                                (when next
                                  (if (eq? mode 'count)
                                    (set! accumulator (+ accumulator 1))
                                    (when numeric?
                                      (let (value (cdr (candidate-required-entry (cadr operator) next)))
                                        (if (exact-integer? value)
                                          (set! accumulator
                                            (case mode
                                              ((sum) (+ accumulator value))
                                              ((min) (if accumulator (min accumulator value) value))
                                              ((max) (if accumulator (max accumulator value) value))
                                              (else #f)))
                                          (set! numeric? #f)))))))
                             (probe (cdr remaining))))
                         (unless bounded?
                           (let (value (and numeric? accumulator))
                             (when value
                               (walk (cdr clauses)
                                     (cons (cons output value) bindings)))))))
                      (else
                       (certificate-for-each-while active?
                        (lambda (row)
                          (when (step!)
                            (let (next (candidate-bind-atom clause row bindings))
                              (when next (walk (cdr clauses) next)))))
                        (rows (car clause)))))))))
            (walk body [])
            changed?))
    (if (> (length schema) +max-certificate-relations+)
      (values 'bounded [])
    (if (not levels)
      (values 'unsupported [])
      (begin
        (certificate-for-each-while active?
         (lambda (entry)
           (certificate-for-each-while active? (lambda (row) (add-row! (car entry) row #f))
                     (caddr entry)))
         (reasoning-snapshot-relations snapshot))
        (certificate-for-each-while active?
         (lambda (fact)
           (add-row! (vector-ref fact 0) (vector-ref fact 1) #f))
         (reasoning-candidate-facts spec))
        (let stratum ((level 0)
                      (maximum (apply max (map cdr levels))))
          (when (and (<= level maximum) (not bounded?))
            (let repeat ()
              (let (changed? #f)
                (certificate-for-each-while active?
                 (lambda (rule)
                   (when (and (not bounded?)
                              (= (cdr (candidate-required-entry
                                       (car (vector-ref rule 0)) levels))
                                 level))
                     (when (evaluate-rule rule)
                       (set! changed? #t))))
                 rules)
                (when (and changed? (not bounded?)) (repeat))))
            (stratum (+ level 1) maximum)))
        (values (if bounded? 'bounded 'complete)
                (if bounded? []
                    (map (lambda (entry)
                           (list (car entry) (replay-relation-arity (cdr entry))
                                 (rows (car entry))))
                         tables))))))))

;; : (-> InspectedCandidate Closure Rows)
(def (query-rows spec closure)
  (let* ((query (vector-ref (reasoning-candidate-query spec) 0))
         (entry (candidate-required-entry (car query) closure)))
    (filter (lambda (row) (and (candidate-bind-atom query row []) #t))
            (caddr entry))))

;;; The generator compares independent replay with a completed native
;;; answer. Mismatch is explicit; it is never reported as a certificate.
;; : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows Nat FiniteEvidence)
(def (candidate-finite-evidence snapshot spec candidate-digest
                                native-status native-rows work-budget)
  (unless (and (exact-integer? work-budget) (> work-budget 0))
    (error "finite evidence requires positive work budget" work-budget))
  (def (result status closure)
    (make-finite-evidence
     status (reasoning-snapshot-identity snapshot)
     (reasoning-snapshot-generation snapshot)
     (reasoning-snapshot-digest snapshot) candidate-digest
     (candidate-finite-program-fingerprint spec)
     (candidate-copy-pairs (vector-ref (reasoning-candidate-query spec) 0))
     work-budget (candidate-copy-pairs closure)))
  (if (or (not (reasoning-snapshot-valid? snapshot))
          (not (eq? native-status 'complete)))
    (result 'unsupported [])
    (let-values (((status closure)
                  (finite-replay snapshot spec work-budget)))
      (case status
        ((complete)
         (cond
          ((not (closure-valid? closure (candidate-schema-of snapshot spec)))
           (result 'bounded []))
          ((candidate-same-row-set? (query-rows spec closure) native-rows)
           (result 'complete closure))
          (else (result 'mismatch []))))
        ((bounded) (result 'bounded []))
        (else (result 'unsupported []))))))

;;; Return only the independently replayed closure when all certificate and
;;; native-answer checks pass. Downstream proof checkers must use this value,
;;; not reread a mutable caller-supplied certificate after verification.
;; : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows FiniteEvidence Nat
;;       (Values Verdict Closure))
(def (candidate-verified-finite-closure snapshot spec candidate-digest
                                        native-status native-rows certificate
                                        work-budget)
  (unless (and (exact-integer? work-budget) (> work-budget 0))
    (error "finite evidence verification needs positive budget" work-budget))
  (if (not (and (finite-evidence? certificate)
                (reasoning-snapshot-valid? snapshot)
                (eq? native-status 'complete)
                (eq? (finite-evidence-status certificate) 'complete)
                (equal? (finite-evidence-snapshot-identity certificate)
                        (reasoning-snapshot-identity snapshot))
                (equal? (finite-evidence-snapshot-generation certificate)
                        (reasoning-snapshot-generation snapshot))
                (equal? (finite-evidence-snapshot-digest certificate)
                        (reasoning-snapshot-digest snapshot))
                (equal? (finite-evidence-candidate-digest certificate)
                        candidate-digest)
                (equal? (finite-evidence-program certificate)
                        (candidate-finite-program-fingerprint spec))
                (equal? (finite-evidence-query certificate)
                        (vector-ref (reasoning-candidate-query spec) 0))
                (closure-valid? (finite-evidence-closure certificate)
                                (candidate-schema-of snapshot spec))))
    (values 'invalid [])
    (let-values (((status closure)
                  (finite-replay snapshot spec work-budget)))
      (case status
        ((bounded) (values 'bounded []))
        ((complete)
         (if (and
              (andmap (lambda (actual supplied)
                        (candidate-same-row-set? (caddr actual) (caddr supplied)))
                      closure (finite-evidence-closure certificate))
              (candidate-same-row-set? (query-rows spec closure) native-rows))
           (values 'valid closure) (values 'invalid [])))
        (else (values 'invalid []))))))

;;; Recompute from the snapshot and inspected program. A supplied closure
;;; cannot authenticate the snapshot or claim more than this finite model.
;; : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows FiniteEvidence Nat Verdict)
(def (candidate-verify-finite-evidence snapshot spec candidate-digest
                                       native-status native-rows certificate
                                       work-budget)
  (let-values (((verdict closure)
                (candidate-verified-finite-closure
                 snapshot spec candidate-digest native-status native-rows
                 certificate work-budget)))
    verdict))
