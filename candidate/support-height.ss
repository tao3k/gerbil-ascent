;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(export grounded-support-heights)

;;; Private graph computation over already verified support. A call owns its
;;; dependency table, labels and pending spine; no annotation survives a subcut.
;; : (forall (n) (-> n [n] HeightRule))
;; : (-> NodeId PremiseIds HeightRule)
(defstruct height-rule (head inputs) final: #t)

;; grounded-support-heights
;; : (forall (n s) (-> [(GroundedEdge n s)] (Membership n) (Membership s) (-> Void) (HeightTable n)))
;; : (-> GroundedEdges NodeMembership SourceMembership (-> Void) HeightTable)
;; | doc m%
;;     Compute finite min/max proof heights from founded seeds. Dependency
;;     indexes and labels belong to this invocation; the charge callback bounds
;;     every admitted edge/premise and every wakeup before any result escapes.
;;
;;     # Examples
;;
;;     ```scheme
;;     (grounded-support-heights '((0 source seed ())) alive removed charge!)
;;     ;; => a fresh table mapping live node 0 to height 0
;;     ```
;;   %
(def (grounded-support-heights edges alive removed probe!)
  (let ((dependents (make-hash-table-eqv)) (heights (make-hash-table-eqv)) (pending []))
    (def (improve! head next)
      (let (prior (hash-get heights head))
        (when (or (not prior) (< next prior))
          (hash-put! heights head next)
          (set! pending (cons head pending)))))
    (def (body-height inputs)
      (let (maximum 0)
        (and (andmap (lambda (id)
                       (probe!)
                       (cond ((hash-get heights id)
                              => (lambda (height) (set! maximum (max maximum height)) #t))
                             (else #f))) inputs)
             maximum)))
    (def (relax-rule! (rule :- height-rule))
      (probe!)
      (cond ((body-height rule.inputs) => (lambda (height) (improve! rule.head (+ height 1))))))
    ;; Finish dependency admission before processing seeds. Sources and empty
    ;; rule bodies may seed a cycle; a cycle alone cannot give itself a label.
    (for-each
     (lambda (edge)
       (probe!)
       (with ([head kind label inputs] edge)
         (when (and (hash-get alive head)
                    (not (and (eq? kind 'source) (hash-get removed label))))
           (if (eq? kind 'rule)
             (let (rule (make-height-rule head inputs))
               (if (null? inputs) (improve! head 1)
                 (for-each (lambda (id)
                             (probe!)
                             (hash-put! dependents id
                               (cons rule (or (hash-get dependents id) [])))) inputs)))
             (improve! head 0))))) edges)
    (until (null? pending)
      (let (id (car pending))
        (set! pending (cdr pending))
        (probe!)
        (for-each relax-rule! (or (hash-get dependents id) []))))
    heights))
