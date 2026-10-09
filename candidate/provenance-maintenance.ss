;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Private retained state over an already verified grounded support graph.
;;; Enumeration and verification belong to provenance-graph. Membership indexes
;;; never order evidence; every bounded phase still traverses the retained edges.
(import (only-in "datum.ss" reasoning-bounded-data? candidate-copy-pairs)
        (only-in "provenance.ss" positive-proof-nodes positive-proof-roots
                 proof-node-id proof-node-row))
(export candidate-make-provenance-maintenance provenance-maintenance?
        provenance-maintenance-rows candidate-provenance-withdraw!
        candidate-provenance-preview-withdraw candidate-provenance-compact
        provenance-maintenance-size)
(defstruct provenance-maintenance (rows-table roots edges sources alive removed))

;;; Counts describe retained graph owners, not allocator or resident memory.
;; : (-> ProvenanceMaintenance (Values Nat Nat Nat))
(def (provenance-maintenance-size state)
  (unless (provenance-maintenance? state) (error "expected provenance maintenance state"))
  (values (hash-length (provenance-maintenance-rows-table state))
          (length (provenance-maintenance-edges state))
          (length (provenance-maintenance-roots state))))

;;; Positive subcuts cannot make a currently unfounded premise live again.
;;; Build a detached header and row index; immutable surviving edges can share
;;; their pairs. Keep the initial source registry and cumulative retired tokens
;;; so low-level selector validation and repeated cuts retain their meaning.
;;; Charge edge, premise, row and root visits before returning any new owner.
;; : (-> ProvenanceMaintenance Nat (Values ProvenanceMaintenance Nat))
(def (candidate-provenance-compact state (max-steps 100000))
  (unless (and (provenance-maintenance? state) (exact-integer? max-steps) (> max-steps 0))
    (error "invalid provenance compaction"))
  (let ((alive (provenance-maintenance-alive state))
        (removed (provenance-maintenance-removed state))
        (rows (make-hash-table-eqv)) (steps 0))
    (def (probe!)
      (set! steps (+ steps 1))
      (when (> steps max-steps) (error "provenance compaction budget exceeded")))
    (let* ((edges
             (filter (lambda (edge)
                       (probe!)
                       (and (hash-get alive (car edge))
                            (not (and (eq? (cadr edge) 'source)
                                      (hash-get removed (caddr edge))))
                            (andmap (lambda (id) (probe!) (hash-get alive id)) (cadddr edge))))
                     (provenance-maintenance-edges state)))
           (roots (filter (lambda (id) (probe!) (hash-get alive id))
                          (provenance-maintenance-roots state))))
      (hash-for-each (lambda (id row)
                       (probe!)
                       (when (hash-get alive id) (hash-put! rows id row)))
                    (provenance-maintenance-rows-table state))
      (values (make-provenance-maintenance rows roots edges
                 (provenance-maintenance-sources state) alive removed) steps))))

;; candidate-make-provenance-maintenance
;; : (forall (row) (-> (VerifiedPositiveProof row) GroundedAlternatives (ProvenanceMaintenance row)))
;; : (-> VerifiedPositiveProof GroundedAlternatives ProvenanceMaintenance)
;; | doc m%
;;     Copy only the certificate admitted by provenance-graph's public opener.
;;     Equality matches the original ID/source membership operations. Indexes
;;     belong to this retained graph; row output still follows its root list.
;;
;;     # Examples
;;
;;     ```scheme
;;     (candidate-make-provenance-maintenance verified-proof alternatives)
;;     ;; => private graph state, independent of certificate pair spines
;;     ```
;;   %
(def (candidate-make-provenance-maintenance proof alternatives)
  (let ((rows (make-hash-table-eqv)) (alive (make-hash-table-eqv))
        (sources (make-hash-table)) (edges (candidate-copy-pairs alternatives)))
    (for-each
     (lambda (node)
       (let (id (proof-node-id node))
         (unless (hash-get alive id)
           (hash-put! rows id (candidate-copy-pairs (proof-node-row node)))
           (hash-put! alive id #t)))) (positive-proof-nodes proof))
    (for-each (lambda (edge)
                (when (eq? (cadr edge) 'source) (hash-put! sources (caddr edge) #t))) edges)
    (make-provenance-maintenance rows (candidate-copy-pairs (positive-proof-roots proof))
                                 edges sources alive (make-hash-table))))

;; maintenance-rows
;; : (forall (row) (-> (ProvenanceMaintenance row) NodeMembership (List row)))
;; : (-> ProvenanceMaintenance NodeMembership Rows)
;; | doc m%
;;     Roots retain certificate order. Copy only rows admitted by the supplied
;;     membership; hash iteration never selects or emits a result row.
;;
;;     # Examples
;;
;;     ```scheme
;;     (maintenance-rows state tentative-alive)
;;     ;; => detached rows before tentative state is published
;;     ```
;;   %
(def (maintenance-rows state alive)
  (map (lambda (id) (candidate-copy-pairs (hash-ref (provenance-maintenance-rows-table state) id)))
       (filter (lambda (id) (hash-get alive id)) (provenance-maintenance-roots state))))

;; provenance-maintenance-rows
;;   : (forall (row) (-> (ProvenanceMaintenance row) (List row)))
;;   : (-> ProvenanceMaintenance Rows)
;;   | doc m%
;;       Copy the last completed query rows in certificate-root order.
;;       Failed withdrawals leave both rows and source-occurrence state intact.
;;     %
(def (provenance-maintenance-rows state)
  (unless (provenance-maintenance? state) (error "expected provenance maintenance state"))
  (maintenance-rows state (provenance-maintenance-alive state)))

;;; Stage one prospective source cut for a surrounding transaction. Graph,
;;; rows and selectors are private immutable owners; withdraw already copies
;;; both mutable memberships before any work. A new state header can share
;;; those owners until withdraw installs its detached memberships. Discarding
;;; a successful preview leaves the original state unchanged.
;;; The surrounding owner serializes mutations of the original state.
;; : (-> ProvenanceMaintenance SourceOccurrences Nat (Values ProvenanceMaintenance Rows Nat))
(def (candidate-provenance-preview-withdraw state selectors (max-steps 100000))
  (unless (provenance-maintenance? state) (error "expected provenance maintenance state"))
  (let (next (make-provenance-maintenance
              (provenance-maintenance-rows-table state)
              (provenance-maintenance-roots state)
              (provenance-maintenance-edges state)
              (provenance-maintenance-sources state)
              (provenance-maintenance-alive state)
              (provenance-maintenance-removed state)))
    (let-values (((rows work) (candidate-provenance-withdraw! next selectors max-steps)))
      (values next rows work))))

;;; DRed preserves the former edge order and probe count exactly. Indexes remove
;;; list membership searches, not bounded work. A cycle cannot seed itself;
;;; remaining founded source/rule support may restore overdeleted facts.
;; candidate-provenance-withdraw!
;;   : (-> ProvenanceMaintenance SourceOccurrences Nat (Values Rows Nat))
;;   | doc m%
;;       Overdelete affected support, then rederive from founded alternatives.
;;       Copies of published memberships belong to this transaction. Validate
;;       every selector before probing, and publish after both phases and row
;;       copying succeed. Retained selectors never borrow caller-owned pairs.
;;
;;       # Examples
;;
;;       ```scheme
;;       (let (before (provenance-maintenance-rows state))
;;         (let-values (((after work) (candidate-provenance-withdraw! state [] 100000)))
;;           (equal? before after)))
;;       ;; => #t
;;       ```
;;     %
(def (candidate-provenance-withdraw! state selectors (max-steps 100000))
  (unless (and (provenance-maintenance? state)
               (exact-integer? max-steps) (> max-steps 0)
               (reasoning-bounded-data? selectors 131072 128) (list? selectors))
    (error "invalid provenance withdrawal"))
  (for-each (lambda (selector)
              (unless (hash-get (provenance-maintenance-sources state) selector)
                (error "unknown provenance source occurrence" selector))) selectors)
  (let ((edges (provenance-maintenance-edges state))
        (selected (make-hash-table))
        (removed (hash-copy (provenance-maintenance-removed state)))
        (alive (hash-copy (provenance-maintenance-alive state)))
        (affected (make-hash-table-eqv)) (steps 0))
    (for-each (lambda (selector)
                (hash-put! selected selector #t) (hash-put! removed selector #t))
              (candidate-copy-pairs selectors))
    ;; : (-> Void)
    ;; Charge exactly one original edge visit; exhaustion publishes nothing.
    (def (probe!)
      (set! steps (+ steps 1))
      (when (> steps max-steps) (error "provenance withdrawal budget exceeded")))
    (for-each
     (lambda (edge)
       (probe!)
       (when (and (eq? (cadr edge) 'source) (hash-get selected (caddr edge)))
         (hash-put! affected (car edge) #t))) edges)
    (let overdelete ()
      (let (changed? #f)
        (for-each
         (lambda (edge)
           (probe!)
           (when (and (eq? (cadr edge) 'rule)
                      (not (hash-get affected (car edge)))
                      (ormap (lambda (id) (hash-get affected id)) (cadddr edge)))
             (hash-put! affected (car edge) #t) (set! changed? #t))) edges)
        (when changed? (overdelete))))
    (hash-for-each (lambda (id _) (hash-remove! alive id)) affected)
    (let rederive ()
      (let (changed? #f)
        (for-each
         (lambda (edge)
           (probe!)
           (when (and (hash-get affected (car edge))
                      (not (hash-get alive (car edge)))
                      (not (and (eq? (cadr edge) 'source) (hash-get removed (caddr edge))))
                      (andmap (lambda (id) (hash-get alive id)) (cadddr edge)))
             (hash-put! alive (car edge) #t) (set! changed? #t))) edges)
        (when changed? (rederive))))
    (let (rows (maintenance-rows state alive))
      (provenance-maintenance-alive-set! state alive)
      (provenance-maintenance-removed-set! state removed)
      (values rows steps))))
