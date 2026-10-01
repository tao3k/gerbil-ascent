;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Bounded, inert rule proposals against a caller-owned snapshot.
;;; A receipt is an observation of one candidate, not source admission.
;;; Shared bounded proposal data and source snapshot value types.
(import (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode))

(export make-reasoning-snapshot reasoning-snapshot?
        reasoning-snapshot-identity
        reasoning-snapshot-generation reasoning-snapshot-digest
        reasoning-snapshot-relations
        reasoning-snapshot-content-digest reasoning-snapshot-valid?
        reasoning-bounded-data?
        make-reasoning-diagnostic reasoning-diagnostic?
        reasoning-diagnostic-code
        reasoning-diagnostic-path reasoning-diagnostic-detail
        make-reasoning-candidate reasoning-candidate-relations
        reasoning-candidate-facts reasoning-candidate-rules
        reasoning-candidate-query reasoning-candidate-limits
        make-candidate-rejection candidate-rejection?
        candidate-rejection-diagnostic
        +max-relations+ +max-rules+ +max-input-facts+
        +max-derived-facts+ +max-output-facts+)

(defstruct reasoning-snapshot (identity generation digest relations))
(defstruct reasoning-diagnostic (code path detail))
(defstruct reasoning-candidate (relations facts rules query limits))
(defstruct candidate-rejection (diagnostic))

(def +max-relations+ 64)
(def +max-rules+ 64)
(def +max-input-facts+ 1024)
(def +max-derived-facts+ 4096)
(def +max-output-facts+ 4096)

;;; Walk untrusted pair trees without recursing through caller-owned input.
;;; The active-path check rejects cycles while allowing shared, acyclic rows.
;;; Cdr steps do not increase nesting depth, so a flat finite list is bounded
;;; by node count rather than an arbitrary list-length depth limit.
;; reasoning-bounded-data?
;;   : (forall (a) (-> a Nat Nat Boolean))
;;   : (-> Datum Nat Nat Boolean)
;;   | doc m%
;;       Check an inert scalar/pair tree before any list traversal or digest.
;;       The result is false for cycles, executable leaves or work exhaustion.
;;       Sharing between finite branches is allowed.
;;
;;       # Examples
;;
;;       ```scheme
;;       (reasoning-bounded-data? '(edge 1 2) 16 8)
;;       ;; => #t
;;       ```
;;     %
(def (reasoning-bounded-data? datum max-nodes max-depth)
  (let (active (make-hash-table-eq))
    (let loop ((pending (list (vector 'enter datum 0)))
               (remaining max-nodes))
      (if (null? pending)
        #t
        (let* ((item (car pending))
               (rest (cdr pending))
               (kind (vector-ref item 0))
               (value (vector-ref item 1))
               (depth (vector-ref item 2)))
          (if (eq? kind 'exit)
            (begin (hash-put! active value #f)
                   (loop rest remaining))
            (cond
             ((<= remaining 0) #f)
             ((pair? value)
              (if (or (> depth max-depth) (hash-get active value))
                #f
                (begin
                  (hash-put! active value #t)
                  (loop
                   (cons (vector 'enter (car value) (+ depth 1))
                         (cons (vector 'enter (cdr value) depth)
                               (cons (vector 'exit value depth) rest)))
                   (- remaining 1)))))
             ((or (null? value) (snapshot-scalar? value))
              (loop rest (- remaining 1)))
             (else #f))))))))

;; : (forall (row) (-> SourceId Nat (Relations row) Digest))
;; : (-> SourceId Nat Relations Digest)
(def (reasoning-snapshot-content-digest identity generation relations)
  (hex-encode
   (sha256
    (string->utf8
     (call-with-output-string ""
       (lambda (port)
         (write (list 'reasoning-snapshot-v1
                      identity generation relations)
                port)))))))

;; : (forall (a) (-> a Boolean))
;; : (-> Datum Boolean)
(def (snapshot-scalar? value)
  (or (exact-integer? value) (boolean? value)
      (symbol? value) (char? value)))

;; : (forall (row) (-> (Row row) Nat Boolean))
;; : (-> Row Nat Boolean)
(def (snapshot-row-valid? row arity)
  (and (list? row) (= (length row) arity)
       (andmap snapshot-scalar? row)))

;; : (forall (row) (-> (Relation row) (Map Symbol Boolean) Nat Boolean))
;; : (-> Relation SeenNames Nat Boolean)
(def (snapshot-relation-valid? entry names remaining-facts)
  (and (list? entry) (= (length entry) 3)
       (symbol? (car entry))
       (not (hash-get names (car entry)))
       (exact-integer? (cadr entry))
       (<= 0 (cadr entry))
       (list? (caddr entry))
       (<= (length (caddr entry)) remaining-facts)
       (andmap (lambda (row) (snapshot-row-valid? row (cadr entry)))
               (caddr entry))
       (begin (hash-put! names (car entry) #t) #t)))

;;; This consistency check is the bounded structural gate. Digest hashing is
;;; deliberately last so malformed or over-limit input cannot enter it.
;;; A visible constructor and mutable Scheme lists make the stored digest
;;; only a claim until current contents are checked. This check establishes
;;; internal consistency, never authority over the named source.
;; : (forall (row) (-> (Snapshot row) Boolean))
;; : (-> ReasoningSnapshot Boolean)
(def (reasoning-snapshot-valid? snapshot)
  (and (reasoning-snapshot? snapshot)
       (or (symbol? (reasoning-snapshot-identity snapshot))
           (string? (reasoning-snapshot-identity snapshot)))
       (exact-integer? (reasoning-snapshot-generation snapshot))
       (<= 0 (reasoning-snapshot-generation snapshot))
       (let ((relations (reasoning-snapshot-relations snapshot))
             (names (make-hash-table))
             (facts 0))
         (and
          (reasoning-bounded-data? relations 131072 128)
          (list? relations)
          (<= (length relations) +max-relations+)
          (andmap
           (lambda (entry)
             (and (snapshot-relation-valid?
                   entry names (- +max-input-facts+ facts))
                  (begin
                    (set! facts (+ facts (length (caddr entry))))
                    #t)))
           relations)
          (equal?
           (reasoning-snapshot-digest snapshot)
           (reasoning-snapshot-content-digest
            (reasoning-snapshot-identity snapshot)
            (reasoning-snapshot-generation snapshot)
            relations))))))

;;; Candidate rows may be caller-owned pairs. Copy nested pairs at the
;;; receipt boundary so later edits to a proposal cannot rewrite evidence.
