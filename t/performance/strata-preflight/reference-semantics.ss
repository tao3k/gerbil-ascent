;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Dependency planning and lattice row semantics over private lowered plans.
;;; Original runtime exports forward to the separate binding owner.
(import (only-in :gerbil-ascent/core/rule-bindings gerbil-ascent-expression-value
                 gerbil-ascent-bind-row gerbil-ascent-head-row)
        (only-in :std/list/list butlast)
        (only-in :gerbil-ascent/core/dependency-graph gerbil-ascent-graph-components))

(export gerbil-ascent-rule-strata
        gerbil-ascent-rule-successors
        gerbil-ascent-lattice-feeds-relation?
        gerbil-ascent-delta-positions
        gerbil-ascent-lattice-key
        gerbil-ascent-lattice-value
        gerbil-ascent-joined-row
        gerbil-ascent-expression-value
        gerbil-ascent-bind-row
        gerbil-ascent-head-row)

;; gerbil-ascent-rule-successors
;;   : (-> RulePlans Nat DenseAdjacency)
;;   | doc m%
;;       Compile source-to-head invalidation edges from admitted rule plans.
;;       Positive, negative and aggregate reads affect every head. Non-reading
;;       clauses add no edge. The fresh graph belongs to immutable analysis;
;;       source rows and mutable engine state are never retained.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-rule-successors [] 2) ;; => #(() ())
;;       ```
;;     %
(def (gerbil-ascent-rule-successors plans count)
  (let (successors (make-vector count []))
    (for-each
     (lambda (rule)
       (for-each
        (lambda (clause)
          (when (memq (vector-ref clause 0) '(atom negation aggregate))
            (let (source (vector-ref (vector-ref clause 1) 0))
              (for-each
               (lambda (head)
                 (vector-set! successors source
                   (cons (vector-ref head 0) (vector-ref successors source))))
               (vector-ref rule 0)))))
        (vector-ref rule 1)))
     plans)
    successors))

(def (gerbil-ascent-lattice-key row)
  (unless (pair? row)
    (error "invalid ASCENT lattice row" row))
  (butlast row))

(def (gerbil-ascent-lattice-value row)
  (last row))

(def (gerbil-ascent-joined-row key value)
  (append key (list value)))

(def (gerbil-ascent-lattice-feeds-relation? rule-plans kinds)
  ;; A lattice refinement can invalidate rows already emitted by an ordinary
  ;; relation that reads its value. Retained source updates must recompute that
  ;; relation from the accepted source snapshot.
  (ormap
   (lambda (rule)
     (and (ormap (lambda (head)
                   (eq? (vector-ref kinds (vector-ref head 0)) 'relation))
                 (vector-ref rule 0))
          (ormap (lambda (clause)
                   (and (eq? (vector-ref clause 0) 'atom)
                        (eq? (vector-ref kinds
                                         (vector-ref (vector-ref clause 1) 0))
                             'lattice)))
                 (vector-ref rule 1))))
   rule-plans))

;;; Negative, aggregate, and lattice-to-relation edges require a later
;;; stratum. A strict edge inside an SCC is invalid. The SCC condensation
;;; order then propagates the minimum strata in one pass over the edges.
;; gerbil-ascent-rule-strata
;;   : (-> RulePlans Nat RelationKinds Strata)
;;   | doc m%
;;       Assign the minimum valid stratum to each declared relation.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-rule-strata '() 1 '#(relation))
;;       ;; => a vector containing stratum 0
;;       ```
;;     %
(def (gerbil-ascent-rule-strata rule-plans relation-count kinds)
  (let ((strata (make-vector relation-count 0))
        (dependencies [])
        (has-strict? #f))
    (for-each
     (lambda (rule)
       (for-each
        (lambda (head)
          (for-each
           (lambda (clause)
             (when (memq (vector-ref clause 0)
                         '(atom negation aggregate))
               (let* ((body-atom (vector-ref clause 1))
                      (kind (vector-ref clause 0))
                      (head-index (vector-ref head 0))
                      (body-index (vector-ref body-atom 0))
                      (lattice-projection?
                       (and (eq? kind 'atom)
                            (eq? (vector-ref kinds body-index) 'lattice)
                            (eq? (vector-ref kinds head-index) 'relation)))
                      (strict? (or (not (eq? kind 'atom)) lattice-projection?)))
                 (when strict? (set! has-strict? #t))
                 (set! dependencies
                   (cons (vector head-index body-index
                                 (if strict? 1 0)
                                 (if lattice-projection?
                                   'lattice-projection kind))
                         dependencies)))))
           (vector-ref rule 1)))
        (vector-ref rule 0)))
     rule-plans)
    ;; Positive dependencies alone always admit stratum zero.
    (when has-strict?
      (let ((successors (make-vector relation-count []))
            (outgoing (make-vector relation-count []))
            (component-of (make-vector relation-count #f)))
        (for-each
         (lambda (dependency)
           (let ((head (vector-ref dependency 0))
                 (body (vector-ref dependency 1)))
             (vector-set! successors body
                          (cons head (vector-ref successors body)))
             (vector-set! outgoing body
                          (cons dependency (vector-ref outgoing body)))))
         dependencies)
        (let (components (gerbil-ascent-graph-components successors))
          (for-each
           (lambda (members)
             (for-each (lambda (node)
                         (vector-set! component-of node members))
                       members))
           components)
          ;; Keep dependency order when selecting the cycle diagnostic.
          (for-each
           (lambda (dependency)
             (when (and (= (vector-ref dependency 2) 1)
                        (eq? (vector-ref component-of (vector-ref dependency 0))
                             (vector-ref component-of (vector-ref dependency 1))))
               (case (vector-ref dependency 3)
                 ((aggregate)
                  (error "unstratifiable ASCENT aggregate cycle"))
                 ((negation)
                  (error "unstratifiable ASCENT negation cycle"))
                 ((lattice-projection)
                  (error "unstratifiable ASCENT lattice projection cycle"))
                 (else
                  (error "unstratifiable ASCENT dependency cycle")))))
           dependencies)
          (for-each
           (lambda (members)
             (let (stratum
                   (foldl (lambda (node prior)
                            (max prior (vector-ref strata node)))
                          0 members))
               (for-each (lambda (node) (vector-set! strata node stratum)) members)
               (for-each
                (lambda (node)
                  (for-each
                   (lambda (dependency)
                     (let* ((head (vector-ref dependency 0))
                            (required (+ stratum (vector-ref dependency 2))))
                       (vector-set! strata head
                                    (max (vector-ref strata head) required))))
                   (vector-ref outgoing node)))
                members)))
           components))))
    strata))

;;; Delta positions count only positive atom scans; guards and generators do
;;; not introduce a relation index into the semi-naive rule plan.
;; gerbil-ascent-delta-positions
;;   : (-> Clauses Strata Nat (List Nat))
;;   | doc m%
;;       Select body atom positions that read the current stratum's delta.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-delta-positions '() '#(0) 0)
;;       ;; => an empty position list
;;       ```
;;     %
(def (gerbil-ascent-delta-positions body strata stratum)
  (let loop ((remaining body) (depth 0) (selected []))
    (if (null? remaining)
      (reverse selected)
      (let (clause (car remaining))
        (if (eq? (vector-ref clause 0) 'atom)
          (loop (cdr remaining) (+ depth 1)
                (if (= (vector-ref strata
                                   (vector-ref (vector-ref clause 1) 0))
                       stratum)
                  (cons depth selected)
                  selected))
          (loop (cdr remaining) depth selected))))))
