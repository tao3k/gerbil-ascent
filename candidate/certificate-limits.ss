;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Resource boundaries for externally supplied certificate lists. Schema,
;;; groundness and proof semantics belong to each verifier. The rule-instance
;;; budget does not replace these independent material-size limits.
(export +max-certificate-relations+ +max-certificate-rows+
        +max-certificate-cells+ +max-certificate-row-arity+
        bounded-list-length unique-rows?)

(def +max-certificate-relations+ 64)
(def +max-certificate-rows+ 4096)
(def +max-certificate-cells+ 32768)
(def +max-certificate-row-arity+ 1024)

;;; Inspect at most the cap's pairs, including for a cyclic input. Checking
;;; length after a complete list traversal cannot enforce this boundary.
;; bounded-list-length
;;   : (forall (a) (-> (List a) Nat (Maybe Nat)))
;;   : (-> Datum Nat (Maybe Nat))
;;   | doc m%
;;       Return the proper list length when it fits the supplied cap, otherwise
;;       false. Improper and cyclic spines terminate at that same boundary.
;;
;;       # Examples
;;
;;       ```scheme
;;       (bounded-list-length '(a b) 2)
;;       ;; => 2
;;       (bounded-list-length '(a b . c) 2)
;;       ;; => #f
;;       ```
;;     %
(def (bounded-list-length items maximum)
  (do ((rest items (cdr rest))
       (count 0 (+ count 1)))
      ((or (null? rest) (not (pair? rest)) (>= count maximum))
       (and (null? rest) count))))

;;; Each check owns its structural-equality table. Callers must establish a
;;; bounded proper row list before invoking this semantic uniqueness check.
;; unique-rows?
;;   : (forall (row) (-> (List row) Boolean))
;;   : (-> BoundedRows Boolean)
;;   | doc m%
;;       Reject structurally equal rows using a fresh private membership table.
;;       This does not validate the row grammar or establish a proof claim.
;;
;;       # Examples
;;
;;       ```scheme
;;       (unique-rows? '((1 2) (1 2)))
;;       ;; => #f
;;       ```
;;     %
(def (unique-rows? rows)
  (let (seen (make-hash-table))
    (andmap
     (lambda (row)
       (if (hash-get seen row)
         #f
         (begin (hash-put! seen row #t) #t)))
     rows)))
