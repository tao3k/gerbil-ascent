;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(export (struct-out support-rule) index-support-rule!)

;;; Private positional protocol shared by founded withdrawal and height reads.
;;; The caller owns the table; input spines come from copied verified support.
;; : (forall (n) (-> n [n] SupportRule))
;; : (-> NodeId PremiseIds SupportRule)
(defstruct support-rule (head inputs) final: #t)

;; index-support-rule!
;; : (forall (n) (-> (DependencyTable n) n [n] (-> Void) Void))
;; : (-> DependencyTable NodeId PremiseIds WorkCharge Void)
;; | doc m%
;;     Register one rule for each premise occurrence in an invocation-owned
;;     table. Repeated premises retain their charge and dependency occurrence.
;;
;;     # Examples
;;
;;     ```scheme
;;     (index-support-rule! dependents 2 '(0 1) charge!)
;;     ;; => rules for head 2 are reachable from both premise IDs
;;     ```
;;   %
(def (index-support-rule! dependents head inputs charge!)
  (let (rule (make-support-rule head inputs))
    (for-each (lambda (id)
                (charge!)
                (hash-put! dependents id (cons rule (or (hash-get dependents id) [])))) inputs)))
