;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil-ascent/candidate/reduction-plan prepare-reduction-row)
        (only-in :gerbil-ascent/candidate/grounding-plan
                 prepare-grounding-atom prepare-grounding-fixed)
        (only-in :gerbil-ascent/candidate/program candidate-variable?))
(export (struct-out stratified-rule) (struct-out stratified-clause)
        prepare-stratified-rule)

;;; Closed syntax plans own no rows, verdicts or budget counters. Producer and
;;; checker prepare separate instances from the inspected candidate.
;; : (-> Symbol HeadRenderer StratifiedClauses Label StratifiedRule)
(defstruct stratified-rule (name head body label) final: #t)
;; : (-> ClauseKind Symbol RowOperation Output Operator RowValue StratifiedClause)
(defstruct stratified-clause (kind relation apply output operator value) final: #t)

;; prepare-stratified-rule
;; : (forall (row) (-> (InspectedRule row) (StratifiedRule row)))
;; : (-> InspectedRule StratifiedRule)
;; | doc m%
;;     Resolve ordered atom, scalar and reduction operations once per replay.
;;     Each matcher borrows a row and extends immutable binding pairs. Head
;;     rendering checks binding presence; false remains a present value.
;;
;;     # Examples
;;
;;     ```scheme
;;     (prepare-stratified-rule (vector '(p ?x) '((s ?x)) 7))
;;     ;; => a private plan without evidence or source rows
;;     ```
;;   %
(def (prepare-stratified-rule rule)
  (with (#(head body label) rule)
    (let (known (make-hash-table-eq size: (length body)))
      (make-stratified-rule (car head)
        (prepare-stratified-head head)
        (map (lambda (clause)
               (match clause
                 (['where . _]
                  (make-stratified-clause 'where #f (prepare-grounding-fixed clause) #f #f #f))
                 (['compute . _]
                  (begin (hash-put! known (cadr clause) #t)
                         (make-stratified-clause 'compute #f (prepare-grounding-fixed clause) #f #f #f)))
                 (['not atom]
                  (make-stratified-clause 'not (car atom) (prepare-grounding-atom atom) #f #f #f))
                 (['reduce output operator atom]
                  (let-values (((match-row value) (prepare-reduction-row atom operator known)))
                    (hash-put! known output #t)
                    (make-stratified-clause 'reduce (car atom) match-row output operator value)))
                 (atom
                  (for-each (lambda (term)
                              (when (and (candidate-variable? term) (not (eq? term '?_)))
                                (hash-put! known term #t))) (cdr atom))
                  (make-stratified-clause 'atom (car atom) (prepare-grounding-atom atom) #f #f #f))))
             body)
        label))))

;;; Fuse required-binding admission with ordered rendering. A missing binding
;;; returns false before a row escapes; literal and false values remain distinct.
;; : (forall (row) (-> (Head row) (-> Bindings (Maybe row))))
;; : (-> InspectedHead CheckedHeadRenderer)
(def (prepare-stratified-head head)
  (foldr
   (lambda (term next)
     (if (candidate-variable? term)
       (lambda (bindings)
         (cond ((assq term bindings)
                => (lambda (entry)
                     (let (tail (next bindings))
                       (and tail (cons (cdr entry) tail)))))
               (else #f)))
       (lambda (bindings)
         (let (tail (next bindings)) (and tail (cons term tail))))))
   (lambda (_bindings) []) (cdr head)))
