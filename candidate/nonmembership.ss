;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Closed-world nonmembership relative to one inspected finite positive
;;; program and one copied input snapshot. This says nothing about whether
;;; the caller supplied every real-world source fact.
(import (only-in :gerbil-ascent/candidate/datum candidate-copy-pairs)
        (only-in :gerbil-ascent/core/rule-bindings gerbil-ascent-bind-row)
        (only-in :gerbil-ascent/candidate/certificate-limits
                 +max-certificate-relations+ +max-certificate-rows+
                 +max-certificate-cells+ +max-certificate-row-arity+
                 bounded-list-length unique-rows?)
        (only-in :gerbil-ascent/candidate/program-identity
                 candidate-positive-program-fingerprint)
        (only-in :gerbil-ascent/candidate/types
                 reasoning-snapshot-identity reasoning-snapshot-generation
                 reasoning-snapshot-digest reasoning-snapshot-relations
                 reasoning-snapshot-valid?
                 reasoning-candidate-facts
                 reasoning-candidate-rules reasoning-candidate-query)
        (only-in :gerbil-ascent/candidate/program
                 candidate-variable? scalar?)
        (only-in :gerbil-ascent/candidate/funs
                 candidate-schema-of
                 candidate-fixed-clause)
        (only-in :gerbil-ascent/candidate/provenance
                 candidate-positive-closed-absence positive-proof-status
                 positive-proof-nodes proof-node-relation proof-node-row
                 positive-rule-body? positive-fixed-clause?))

(export candidate-positive-nonmembership
        candidate-verify-positive-nonmembership
        positive-nonmembership? positive-nonmembership-status
        positive-nonmembership-snapshot-identity
        positive-nonmembership-snapshot-generation
        positive-nonmembership-snapshot-digest
        positive-nonmembership-candidate-digest
        positive-nonmembership-program-fingerprint
        positive-nonmembership-query positive-nonmembership-work-budget
        positive-nonmembership-closure)

(defstruct positive-nonmembership
  (status snapshot-identity snapshot-generation snapshot-digest
          candidate-digest program-fingerprint query work-budget closure))

;; : (forall (row) (-> (Closure row) Boolean))
;; : (-> Datum Boolean)
(def (certificate-size-valid? closure)
  (let ((relation-count
         (bounded-list-length closure +max-certificate-relations+))
        (rows 0)
        (cells 0))
    (and relation-count
         (andmap
          (lambda (entry)
            (and (equal? (bounded-list-length entry 3) 3)
                 (let ((row-list (caddr entry)))
                   (let (count
                         (bounded-list-length
                          row-list (- +max-certificate-rows+ rows)))
                     (and count
                          (begin (set! rows (+ rows count)) #t)
                          (andmap
                           (lambda (row)
                             (let (width
                                   (bounded-list-length
                                    row
                                    (min +max-certificate-row-arity+
                                         (- +max-certificate-cells+ cells))))
                               (and width
                                    (begin (set! cells (+ cells width))
                                           #t))))
                           row-list))))))
          closure))))

;; : (forall (a) (-> (List a) Boolean))
;; : (-> Query Boolean)
(def (ground-query? query)
  (and (list? query) (pair? query)
       (andmap
        (lambda (term)
          (and (scalar? term)
               (not (candidate-variable? term))
               (not (eq? term '?_))))
        (cdr query))))

;;; Certificates use two-element list declarations; the shared candidate
;;; schema uses pairs for name-to-arity lookup.
(def (certificate-schema-of snapshot spec)
  (map (lambda (entry) (list (car entry) (cdr entry)))
       (candidate-schema-of snapshot spec)))

;; candidate-positive-nonmembership
;;   : (forall (row) (-> (Snapshot row) (Candidate row) Digest Status (Rows row) Nat PositiveNonmembership))
;;   : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows Nat PositiveNonmembership)
;;   | doc m%
;;       Produce a closed-relation certificate for a missing ground tuple
;;       only after complete native execution and finite positive saturation.
;;       Non-ground or nonpositive programs never receive an absence claim.
;;
;;       # Examples
;;
;;       ```scheme
;;       (candidate-positive-nonmembership
;;         snapshot spec digest 'complete [] 1000)
;;       ;; => complete closure certificate, bounded, or unsupported
;;       ```
;;     %
(def (candidate-positive-nonmembership snapshot spec candidate-digest
                                       native-status native-rows max-steps)
  (unless (and (exact-integer? max-steps) (> max-steps 0))
    (error "invalid nonmembership work budget" max-steps))
  (let (query (vector-ref (reasoning-candidate-query spec) 0))
    (def (result status closure)
      (make-positive-nonmembership
       status (reasoning-snapshot-identity snapshot)
       (reasoning-snapshot-generation snapshot)
       (reasoning-snapshot-digest snapshot)
       candidate-digest (candidate-positive-program-fingerprint spec)
       (candidate-copy-pairs query) max-steps closure))
    (if (or (not (reasoning-snapshot-valid? snapshot))
            (not (eq? native-status 'complete))
            (pair? native-rows)
            (not (ground-query? query))
            (not (andmap positive-rule-body?
                         (reasoning-candidate-rules spec))))
      (result 'unsupported [])
      (if (> (length (certificate-schema-of snapshot spec)) +max-certificate-relations+)
        (result 'bounded [])
      (let* ((witness
              (candidate-positive-closed-absence
               snapshot spec candidate-digest native-status
               native-rows max-steps))
             (status (positive-proof-status witness)))
        (case status
          ((bounded) (result 'bounded []))
          ((closed-absent)
           ;; Group the admitted proof once. The ordered schema still owns
           ;; declaration order; reversing each bucket restores node order.
           (let (grouped (make-hash-table-eq))
             (for-each
              (lambda (node)
                (let (name (proof-node-relation node))
                  (hash-put! grouped name
                    (cons (proof-node-row node)
                          (or (hash-get grouped name) [])))))
              (positive-proof-nodes witness))
             (let (closure
                   (map
                    (lambda (declaration)
                      (list
                       (car declaration) (cadr declaration)
                       (map candidate-copy-pairs
                            (reverse (or (hash-get grouped (car declaration)) [])))))
                    (certificate-schema-of snapshot spec)))
               (if (certificate-size-valid? closure)
                 (result 'complete closure)
                 (result 'bounded [])))))
          (else (result 'unsupported []))))))))

;;; Lower only static term kinds, after certificate admission. Variable names
;;; remain candidate symbols; this plan makes no fresh-binding assumption.
;; : (-> Terms BindingPatterns)
(def (binding-patterns terms (wildcards? #t))
  (map (lambda (term)
         (cons (cond ((and wildcards? (eq? term '?_)) 'wildcard)
                     ((candidate-variable? term) 'variable)
                     (else 'literal))
               term))
       terms))

;; : (forall (v) (-> (Patterns v) (Bindings v) (Row v)))
;; : (-> BindingPatterns Bindings Row)
(def (head-row head bindings)
  (map (lambda (term)
         (if (eq? (car term) 'variable)
           (cdr (assq (cdr term) bindings))
           (cdr term)))
       head))

;;; The checker treats the supplied closure as an inductive invariant:
;;; every input tuple belongs to it, and every rule instance over it has
;;; its head in it. The least fixed point is therefore a subset. Checking
;;; target absence is sound even if the certificate has extra tuples.
;; candidate-verify-positive-nonmembership
;;   : (forall (row) (-> (Snapshot row) (Candidate row) Digest Status (Rows row) PositiveNonmembership Nat Verdict))
;;   : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows PositiveNonmembership Nat Verdict)
;;   | doc m%
;;       Independently check input coverage, every finite rule instance,
;;       absent ground target, and exact snapshot/program/query binding.
;;       The verifier's separate work cap can return bounded.
;;
;;       # Examples
;;
;;       ```scheme
;;       (candidate-verify-positive-nonmembership
;;         snapshot spec digest 'complete [] certificate 1000)
;;       ;; => valid, bounded, or invalid
;;       ```
;;     %
(def (candidate-verify-positive-nonmembership/valid-snapshot
      snapshot spec candidate-digest native-status native-rows
      certificate max-checks)
  (unless (and (exact-integer? max-checks) (> max-checks 0))
    (error "invalid nonmembership verification budget" max-checks))
  (let* ((query (vector-ref (reasoning-candidate-query spec) 0))
         (schema (certificate-schema-of snapshot spec))
         (closure (and (positive-nonmembership? certificate)
                       (positive-nonmembership-closure certificate)))
         (preflight
          (and (certificate-size-valid? closure)
               (= (length closure) (length schema))
               (andmap
                (lambda (entry)
                  (and (list? entry) (= (length entry) 3)
                       (list? (caddr entry))))
                closure)
               (+ 1
                  (apply + (map (lambda (entry) (length (caddr entry)))
                                closure))
                  (apply +
                         (map (lambda (entry) (length (caddr entry)))
                              (reasoning-snapshot-relations snapshot)))
                  (length (reasoning-candidate-facts spec))))))
    (cond
     ((not
       (and (positive-nonmembership? certificate)
              (reasoning-snapshot-valid? snapshot)
              (eq? (positive-nonmembership-status certificate) 'complete)
              (eq? native-status 'complete)
              (null? native-rows)
              (ground-query? query)
              (andmap positive-rule-body?
                      (reasoning-candidate-rules spec))
              (equal? (positive-nonmembership-snapshot-identity certificate)
                      (reasoning-snapshot-identity snapshot))
              (equal? (positive-nonmembership-snapshot-generation certificate)
                      (reasoning-snapshot-generation snapshot))
              (equal? (positive-nonmembership-snapshot-digest certificate)
                      (reasoning-snapshot-digest snapshot))
              (equal? (positive-nonmembership-candidate-digest certificate)
                      candidate-digest)
              (equal?
               (positive-nonmembership-program-fingerprint certificate)
               (candidate-positive-program-fingerprint spec))
              (equal? (positive-nonmembership-query certificate) query)
              preflight
              (equal? (map (lambda (entry) (list (car entry) (cadr entry)))
                           closure)
                      schema)))
      'invalid)
     ((> preflight max-checks) 'bounded)
     ((not
       (andmap
        (lambda (entry)
          (and (unique-rows? (caddr entry))
               (andmap
                (lambda (row)
                  (and (list? row)
                       (= (length row) (cadr entry))
                       (andmap scalar? row)))
                (caddr entry))))
        closure))
     'invalid)
     (else
      ;; Empty, singleton and pair schemas have bounded direct lookup; a
      ;; symbol table pays for itself only for the general schema shape.
      (let* ((steps preflight) (bounded? #f) (invalid? #f)
             (direct? (match closure ([] #t) ([_] #t) ([_ _] #t) (else #f)))
             (index (if direct? [] (make-hash-table-eq size: (length closure)))))
        (def (relation-entry name)
          (if direct?
            (let (entry (assq name index)) (and entry (cdr entry)))
            (hash-get index name)))
        ;; This checker owns its index after size, binding and row admission.
        ;; Keep the supplied row sequence for enumeration and budget charging;
        ;; the membership table never supplies an iteration order.
        (for-each
         (lambda (entry)
           (let (present (make-hash-table))
             (for-each (lambda (row) (hash-put! present row #t)) (caddr entry))
             ;; Retain assq's first-declaration behavior for supplied schemas.
             (unless (relation-entry (car entry))
               (let (value (cons (caddr entry) present))
                 (if direct?
                   (set! index (cons (cons (car entry) value) index))
                   (hash-put! index (car entry) value))))))
         closure)
        (def (rows name)
          (let (entry (relation-entry name))
            (if entry (car entry) [])))
        (def (contains? name row)
          (let (entry (relation-entry name))
            (and entry (hash-get (cdr entry) row))))
        (unless bounded?
          (for-each
         (lambda (entry)
           (for-each
            (lambda (row)
              (unless (contains? (car entry) row)
                (set! invalid? #t)))
            (caddr entry)))
         (reasoning-snapshot-relations snapshot)))
        (unless bounded?
          (for-each
         (lambda (fact)
           (unless (contains? (vector-ref fact 0)
                              (vector-ref fact 1))
             (set! invalid? #t)))
         (reasoning-candidate-facts spec)))
        (when (and (not bounded?)
                   (contains? (car query) (cdr query)))
          (set! invalid? #t))
        (unless (or bounded? invalid?)
          (for-each
           (lambda (rule)
             ;; Prepare this rule once, keeping body order and row ownership.
             ;; A descriptor is (fixed? payload rows); fixed clauses retain
             ;; their checked scalar evaluator and their original work charge.
             (let* ((head (vector-ref rule 0))
                    ;; An identical positive body atom witnesses head
                    ;; membership for every successful instance. Keep walking
                    ;; and charging all instances; only the terminal lookup is
                    ;; redundant. Wildcard heads receive no such admission.
                    (covered-head?
                     (and (not (memq '?_ (cdr head)))
                          (ormap (lambda (clause)
                                   (and (not (positive-fixed-clause? clause))
                                        (equal? head clause)))
                                 (vector-ref rule 1))))
                    (head-patterns (if covered-head? [] (binding-patterns (cdr head) #f)))
                    (head-entry (and (not covered-head?) (relation-entry (car head))))
                    (body (map (lambda (clause)
                                 (if (positive-fixed-clause? clause)
                                   (vector #t clause [])
                                   (vector #f (binding-patterns (cdr clause))
                                           (rows (car clause)))))
                               (vector-ref rule 1))))
               (def (walk remaining bindings)
                 (unless (or bounded? invalid?)
                   (if (null? remaining)
                     (unless (or covered-head?
                                 (and head-entry
                                      (hash-get (cdr head-entry)
                                                (head-row head-patterns bindings))))
                       (set! invalid? #t))
                     (let (clause (car remaining))
                       (if (vector-ref clause 0)
                         (begin
                           (set! steps (+ steps 1))
                           (if (> steps max-checks)
                             (set! bounded? #t)
                             (let (next
                                   (candidate-fixed-clause
                                    (vector-ref clause 1) bindings))
                               (when next
                                 (walk (cdr remaining) next)))))
                         (for-each
                          (lambda (row)
                            (unless (or bounded? invalid?)
                              (set! steps (+ steps 1))
                              (if (> steps max-checks)
                                (set! bounded? #t)
                                (let (next
                                      (gerbil-ascent-bind-row
                                       (vector-ref clause 1) row bindings))
                                  (when next
                                    (walk (cdr remaining) next))))))
                          (vector-ref clause 2)))))))
               (walk body [])))
           (reasoning-candidate-rules spec)))
        (cond
         (invalid? 'invalid)
         (bounded? 'bounded)
         (else 'valid)))))))

;;; The public checker validates the mutable snapshot before any accessor
;;; or size calculation. A malformed or oversized external certificate
;;; returns invalid; it never gets an unbounded list traversal.
;; : (forall (row) (-> (Snapshot row) (Candidate row) Digest Status (Rows row) PositiveNonmembership Nat Verdict))
;; : (-> ReasoningSnapshot InspectedCandidate Digest Status Rows PositiveNonmembership Nat Verdict)
(def (candidate-verify-positive-nonmembership
      snapshot spec candidate-digest native-status native-rows
      certificate max-checks)
  (if (reasoning-snapshot-valid? snapshot)
    (candidate-verify-positive-nonmembership/valid-snapshot
     snapshot spec candidate-digest native-status native-rows
     certificate max-checks)
    'invalid))
