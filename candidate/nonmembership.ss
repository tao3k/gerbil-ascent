;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Closed-world nonmembership relative to one inspected finite positive
;;; program and one copied input snapshot. This says nothing about whether
;;; the caller supplied every real-world source fact.
(import (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :gerbil-ascent/candidate/types
                 reasoning-snapshot-identity reasoning-snapshot-generation
                 reasoning-snapshot-digest reasoning-snapshot-relations
                 reasoning-snapshot-valid?
                 reasoning-candidate-relations reasoning-candidate-facts
                 reasoning-candidate-rules reasoning-candidate-query
                 reasoning-candidate-limits)
        (only-in :gerbil-ascent/candidate/program
                 candidate-variable? scalar?)
        (only-in :gerbil-ascent/candidate/provenance
                 candidate-positive-closed-absence positive-proof-status
                 positive-proof-nodes proof-node-relation proof-node-row
                 positive-rule-body? positive-fixed-clause?
                 positive-apply-fixed-clause))

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

;;; Independent hard limits for externally supplied certificate material.
;;; The caller's max-checks is a rule-instance budget, not a memory bound.
(def +max-certificate-relations+ 64)
(def +max-certificate-rows+ 4096)
(def +max-certificate-cells+ 32768)
(def +max-certificate-row-arity+ 1024)

;; : (forall (a) (-> (List a) Nat (Maybe Nat)))
;; : (-> Datum Nat (Maybe Nat))
(def (bounded-list-length items maximum)
  ;; Stop at the cap even for a cyclic or adversarial list; a fold would
  ;; traverse the entire input before checking the budget.
  (do ((rest items (cdr rest))
       (count 0 (+ count 1)))
      ((or (null? rest) (not (pair? rest)) (>= count maximum))
       (and (null? rest) count))))

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

;;; Freeze certificate-owned pairs without changing scalar leaves.
;; : (forall (a) (-> (PairTree a) (PairTree a)))
;; : (-> Datum Datum)
(def (copy-pairs datum)
  (if (pair? datum)
    (cons (copy-pairs (car datum)) (copy-pairs (cdr datum)))
    datum))

;; : (forall (p) (-> (InspectedProgram p) Digest))
;; : (-> InspectedCandidate Digest)
(def (program-fingerprint spec)
  (let (datum
        (list
         'positive-program-v1
         (reasoning-candidate-relations spec)
         (map (lambda (fact)
                (list (vector-ref fact 0)
                      (vector-ref fact 1)
                      (vector-ref fact 2)))
              (reasoning-candidate-facts spec))
         (map (lambda (rule)
                (list (vector-ref rule 0)
                      (vector-ref rule 1)
                      (vector-ref rule 2)))
              (reasoning-candidate-rules spec))
         (vector-ref (reasoning-candidate-query spec) 0)
         (reasoning-candidate-limits spec)))
    (hex-encode
     (sha256
      (string->utf8
       (call-with-output-string ""
         (lambda (port) (write datum port))))))))

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

;; : (forall (a) (-> (Snapshot a) (Program a) Schema))
;; : (-> ReasoningSnapshot InspectedCandidate Schema)
(def (schema-of snapshot spec)
  (append
   (map (lambda (entry) (list (car entry) (cadr entry)))
        (reasoning-snapshot-relations snapshot))
   (map (lambda (entry) (list (car entry) (cdr entry)))
        (reasoning-candidate-relations spec))))

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
       candidate-digest (program-fingerprint spec)
       (copy-pairs query) max-steps closure))
    (if (or (not (reasoning-snapshot-valid? snapshot))
            (not (eq? native-status 'complete))
            (pair? native-rows)
            (not (ground-query? query))
            (not (andmap positive-rule-body?
                         (reasoning-candidate-rules spec))))
      (result 'unsupported [])
      (let* ((witness
              (candidate-positive-closed-absence
               snapshot spec candidate-digest native-status
               native-rows max-steps))
             (status (positive-proof-status witness)))
        (case status
          ((bounded) (result 'bounded []))
          ((closed-absent)
           (let (nodes (positive-proof-nodes witness))
             (let (closure
                   (map
                    (lambda (declaration)
                      (list
                       (car declaration) (cadr declaration)
                       (map (lambda (node)
                              (copy-pairs (proof-node-row node)))
                            (filter
                             (lambda (node)
                               (eq? (proof-node-relation node)
                                    (car declaration)))
                             nodes))))
                    (schema-of snapshot spec)))
               (if (certificate-size-valid? closure)
                 (result 'complete closure)
                 (result 'bounded [])))))
          (else (result 'unsupported [])))))))

;; : (forall (v) (-> (Atom v) (Row v) (Bindings v) (Maybe (Bindings v))))
;; : (-> Atom Row Bindings (Maybe Bindings))
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

;; : (forall (v) (-> (Atom v) (Bindings v) (Row v)))
;; : (-> Atom Bindings Row)
(def (head-row head bindings)
  (map (lambda (term)
         (if (candidate-variable? term)
           (cdr (assq term bindings))
           term))
       (cdr head)))

;; : (forall (a) (-> (List a) Boolean))
;; : (-> Rows Boolean)
(def (unique-rows? rows)
  (let (seen (make-hash-table))
    (andmap
     (lambda (row)
       (if (hash-get seen row)
         #f
         (begin (hash-put! seen row #t) #t)))
     rows)))

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
         (schema (schema-of snapshot spec))
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
               (program-fingerprint spec))
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
      (let ((steps preflight) (bounded? #f) (invalid? #f)
            (index
             (map
              (lambda (entry)
                (let (present (make-hash-table))
                  (for-each
                   (lambda (row) (hash-put! present row #t))
                   (caddr entry))
                  (cons (car entry) present)))
              closure)))
        (def (rows name)
          (let (entry (assq name closure))
            (if entry (caddr entry) [])))
        (def (contains? name row)
          (let (entry (assq name index))
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
             (let ((head (vector-ref rule 0))
                   (body (vector-ref rule 1)))
               (def (walk remaining bindings)
                 (unless (or bounded? invalid?)
                   (if (null? remaining)
                     (unless (contains? (car head)
                                        (head-row head bindings))
                       (set! invalid? #t))
                     (let (clause (car remaining))
                       (if (positive-fixed-clause? clause)
                         (begin
                           (set! steps (+ steps 1))
                           (if (> steps max-checks)
                             (set! bounded? #t)
                             (let (next
                                   (positive-apply-fixed-clause
                                    clause bindings))
                               (when next
                                 (walk (cdr remaining) next)))))
                         (for-each
                          (lambda (row)
                            (unless (or bounded? invalid?)
                              (set! steps (+ steps 1))
                              (if (> steps max-checks)
                                (set! bounded? #t)
                                (let (next
                                      (bind-atom clause row bindings))
                                  (when next
                                    (walk (cdr remaining) next))))))
                          (rows (car clause))))))))
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
