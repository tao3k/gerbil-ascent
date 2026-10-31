;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import "support-dependencies.ss")
(export grounded-support-withdraw!)

;; grounded-support-withdraw!
;; : (forall (n s) (-> [(GroundedEdge n s)] [n] (Membership n) (Membership n) (Membership s) (-> Void) Void))
;; : (-> GroundedEdges OrderedSeeds AffectedNodes TentativeAlive RemovedSources WorkCharge Void)
;; | doc m%
;;     Close overdeletion from ordered source seeds, then restore only founded
;;     support. Every mutable table belongs to the caller's tentative cut;
;;     no result or published membership escapes on budget exhaustion.
;;
;;     # Examples
;;
;;     ```scheme
;;     (grounded-support-withdraw! edges seeds affected tentative-alive removed charge!)
;;     ;; => tentative-alive contains exactly the remaining founded nodes
;;     ```
;;   %
(def (grounded-support-withdraw! edges seeds affected alive removed probe!)
  (let ((dependents (make-hash-table-eqv)) (pending seeds))
    (for-each (lambda (edge)
                (probe!)
                (with ([head kind _ inputs] edge)
                  (when (eq? kind 'rule)
                    (index-support-rule! dependents head inputs probe!)))) edges)
    (def (overdelete! (rule :- support-rule))
      (probe!)
      (unless (hash-get affected rule.head)
        (hash-put! affected rule.head #t)
        (set! pending (cons rule.head pending))))
    (until (null? pending)
      (let (id (car pending))
        (set! pending (cdr pending))
        (probe!)
        (for-each overdelete! (or (hash-get dependents id) []))))
    (hash-for-each (lambda (id _)
                     (probe!)
                     (hash-remove! alive id)) affected)
    (def (restore! head inputs)
      (when (and (hash-get affected head) (not (hash-get alive head))
                 (andmap (lambda (id) (probe!) (hash-get alive id)) inputs))
        (hash-put! alive head #t)
        (set! pending (cons head pending))))
    (def (restore-rule! (rule :- support-rule))
      (probe!)
      (restore! rule.head rule.inputs))
    ;; One seed pass admits unchanged source alternatives, candidate facts and
    ;; already founded rule bodies. A cycle without such support remains dead.
    (for-each (lambda (edge)
                (probe!)
                (with ([head kind label inputs] edge)
                  (unless (and (eq? kind 'source) (hash-get removed label))
                    (restore! head inputs)))) edges)
    (until (null? pending)
      (let (id (car pending))
        (set! pending (cdr pending))
        (probe!)
        (for-each restore-rule! (or (hash-get dependents id) []))))))
