;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Native dependency invalidation selects components; the evaluator owns
;;; reuse capsules, mutable rows, budget accounting and atomic publication.
(import (only-in :std/list/list-builder with-list-builder)
        (only-in "source-log.ss" gerbil-ascent-source-log-equal?)
        (only-in "source-snapshot.ss" gerbil-ascent-source-log-snapshot-equal?
                 gerbil-ascent-source-snapshot-scalar?)
        (only-in "activation.ss" gerbil-ascent-activate-rule)
        (only-in :clan/poo/object .ref)
        (only-in "scheme-checked.ss" relational-stable-procedure?
                 relational-scalar?)
        (only-in :gerbil-ascent/core/positive-plan gerbil-ascent-positive-plan gerbil-ascent-positive-plan-with-outputs)
        (only-in :gerbil-ascent/core/dependency-graph gerbil-ascent-graph-close!)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-canonical-hash-index-provider?)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-canonical-set-storage-provider?))
(export gerbil-ascent-update-eligible? gerbil-ascent-update-selection
        gerbil-ascent-update-active-plans gerbil-ascent-select-rule-plans)

;; gerbil-ascent-update-eligible?
;; : (forall (p s) (-> p (Maybe s) Boolean))
;; : (-> Program (Maybe SourceSnapshot) Boolean)
;; | doc m%
;;     Check declaration eligibility without constructing a source snapshot,
;;     reading rows or computing dependency closure. Rule callbacks and lattice
;;     joins must be registered closed procedures; storage and index providers
;;     must be the built-ins. This predicate invokes no callback. Only
;;     immutable scalar source and literal values may enter completed-result
;;     reuse. Trusted built-in field predicates certify source values at
;;     admission; otherwise inspect the candidate rows. Other field callbacks
;;     or an opaque lookup may observe or change state outside the read graph.
;;     Owned materializations share only a pure scalar classification. Exact
;;     candidate/row identity is required; opaque field predicates still reject.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-update-eligible? native-program)
;;     ;; => #t for declarations supporting completed-closure reuse
;;     ```
;;   %
(def (gerbil-ascent-update-eligible? candidate (source-cut #f))
  (def (pure-terms? terms)
    (andmap (lambda (term)
              (let (kind (.ref term 'kind))
                (and (memq kind '(variable wildcard literal))
                     (or (not (eq? kind 'literal))
                         (relational-scalar? (.ref term 'value)))))) terms))
  (def (trusted-field? predicate)
    (or (eq? predicate relational-scalar?)
        (eq? predicate exact-integer?)))
  (def (scalar-source? relation index)
    (let (predicates (.ref relation 'field-predicates))
      (and (andmap trusted-field? predicates)
           ;; Core declarations may omit field checks. Their row spines are
           ;; owned by Session, but nested values remain caller-owned. Scan
           ;; only this unchecked case; checked scalar declarations already
           ;; established the invariant during source admission.
           (or (pair? predicates)
               (and source-cut
                    (gerbil-ascent-source-snapshot-scalar?
                     source-cut candidate index (.ref relation 'rows)))
               (andmap (lambda (row) (andmap relational-scalar? row))
                       (.ref relation 'rows))))))
  (def (stable-clause? clause)
    (case (.ref clause 'ascent-clause-kind)
      ((atom negation) (pure-terms? (.ref clause 'terms)))
      ((aggregate) (and (pure-terms? (.ref clause 'terms))
                        (not (.ref clause 'output-pattern))
                        (relational-stable-procedure? (.ref clause 'aggregate))))
      ((guard) (relational-stable-procedure? (.ref clause 'predicate)))
      ((binding) (relational-stable-procedure? (.ref clause 'compute)))
      (else #f)))
  ;; Both lists have the exact declaration count; multi-list andmap's truncating
  ;; behavior cannot omit a declaration. Each occurrence retains admission.
  (and (andmap (lambda (relation index)
                 (and (scalar-source? relation index)
                      (gerbil-ascent-canonical-hash-index-provider?
                       (.ref relation 'index-provider))
                      (if (eq? (.ref relation 'storage-kind) 'lattice)
                        (relational-stable-procedure? (.ref relation 'join))
                        (gerbil-ascent-canonical-set-storage-provider?
                         (.ref relation 'storage-provider)))))
               (.ref candidate 'relations) (iota (length (.ref candidate 'relations))))
       (andmap (lambda (rule)
                 (and (andmap (lambda (head) (pure-terms? (.ref head 'terms)))
                              (.ref rule 'heads))
                      (andmap stable-clause? (.ref rule 'body))))
               (.ref candidate 'rules))))

;; gerbil-ascent-update-selection
;; : (forall (p r a s) (-> (Vector (SourceLog r)) p a (Maybe s) (Maybe Vector)))
;;   : (-> SourceLogVector Program Analysis (Maybe SourceSnapshot) (Maybe AffectedRelations))
;;   | doc m%
;;       Compare source logs and close the affected set through native plans.
;;       Only built-in storage/index providers and registered closed procedures
;;       qualify. An opaque callback/provider returns false and keeps full
;;       recomputation.
;;       A prepared cut certifies only exact candidate/log/row root identity.
;;       Without matching evidence, compare the complete ordered source values.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-update-selection old prospective analysis)
;;       ;; => a fresh affected-relation bitmap, or #f for an opaque provider
;;       ```
;;     %
(def (gerbil-ascent-update-selection previous candidate analysis (source-cut #f))
  (let* ((relations (.ref candidate 'relations))
         (old-relations (vector->list previous))
         (count (length relations))
         (affected (make-vector count #f)))
    (let (eligible?
          (and (= count (length old-relations))
               (gerbil-ascent-update-eligible? candidate source-cut)))
      (if (not eligible?)
          #f
          (begin
            (for-each
             (lambda (old new index)
               (let (rows (.ref new 'rows))
                 (unless (or (and source-cut
                                  (gerbil-ascent-source-log-snapshot-equal?
                                   source-cut candidate index old rows))
                             (gerbil-ascent-source-log-equal? (car old) (cdr old) rows))
                   (vector-set! affected index #t))))
             old-relations relations (iota count))
            (gerbil-ascent-graph-close! (vector-ref analysis 6) affected)
            affected)))))

;;; Selection owns only partial spines. Full survivors retain their identity;
;;; after the first rejection, every surviving pair is copied in source order.
;;; The supplied projection reads immutable metadata and invokes no user code.
(defrule (select-affected affected items (item relation))
  (let ((bitmap affected) (source items))
    (def (keep? item) (vector-ref bitmap relation))
    (let scan ((remaining source))
      (match remaining
        ([] source)
        ([item . rest]
         (cond
           ((keep? item) (scan rest))
           ((eq? remaining source) (filter keep? rest))
           (else
            (with-list-builder (collect)
              ;; Earlier items already passed admission; copy without rechecking.
              (let prefix ((pending source))
                (unless (eq? pending remaining)
                  (collect (car pending)) (prefix (cdr pending))))
              (for-each (lambda (item) (when (keep? item) (collect item))) rest)))))))))

;; : (forall (a) (-> (Vector [a]) Vector (Vector [a])))
;; gerbil-ascent-select-rule-plans
;;   : (-> RulePlansByStratum AffectedRelations RulePlansByStratum)
;;   | doc m%
;;       Project affected outputs in order without allocating variable frames.
;;       Full survivors retain identity; partial heads share lowered body slots.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-select-rule-plans '#() '#())
;;       ;; => '#()
;;       ```
;;     %
(def (gerbil-ascent-select-rule-plans full-active-by-stratum affected)
  (vector-map
   (lambda (rules)
     (filter-map
      (lambda (rule)
        (let (heads (select-affected affected (vector-ref rule 0)
                       (head (vector-ref head 0))))
          (and (pair? heads)
               (if (eq? heads (vector-ref rule 0))
                 rule
                 (let* ((full-plan (vector-ref rule 5))
                        ;; Head filtering leaves body slots unchanged. Share
                        ;; lowered atoms and project ordered outputs; unsupported
                        ;; full plans retain normal lowering of the selected heads.
                        (plan
                         (if full-plan
                           (gerbil-ascent-positive-plan-with-outputs
                            full-plan
                            (select-affected affected (vector-ref full-plan 0)
                              (output (vector-ref (vector-ref output 0) 0))))
                           (gerbil-ascent-positive-plan
                            (vector heads (vector-ref rule 1)
                                    (vector-ref rule 2) (vector-ref rule 3))))))
                   (vector heads (vector-ref rule 1) (vector-ref rule 2)
                           (vector-ref rule 3) (vector-ref rule 4) plan))))))
      rules))
   full-active-by-stratum))

;; gerbil-ascent-update-active-plans
;; : (forall (a) (-> (Vector [a]) Vector (Vector [a])))
;; : (-> ActiveStrata AffectedRelations ActiveStrata)
;; | doc m%
;;     A selected rule preserves its immutable plan when every head survives;
;;     partial-head rules receive a new plan and a fresh engine-owned frame.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-update-active-plans '#() '#())
;;     ;; => '#()
;;     ```
;;   %
(def (gerbil-ascent-update-active-plans full-active-by-stratum affected)
  (vector-map
   (lambda (rules)
     (map (lambda (rule)
            ;; Full survivors retain their original frame and identity. A
            ;; projected six-slot plan needs a fresh private activation.
            (if (= (vector-length rule) 7) rule
              (gerbil-ascent-activate-rule rule))) rules))
   (gerbil-ascent-select-rule-plans full-active-by-stratum affected)))
