;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Pure planning over private lowered rule vectors. These functions do not
;;; retain relation state and are shared by the serial execution path.
(import (only-in :std/list/list butlast))

(export gerbil-ascent-rule-strata
        gerbil-ascent-lattice-feeds-relation?
        gerbil-ascent-delta-positions
        gerbil-ascent-lattice-key
        gerbil-ascent-lattice-value
        gerbil-ascent-joined-row
        gerbil-ascent-expression-value
        gerbil-ascent-bind-row
        gerbil-ascent-head-row)

(def (gerbil-ascent-lattice-key row)
  (unless (pair? row)
    (error "invalid ASCENT lattice row" row))
  (butlast row))

(def (gerbil-ascent-lattice-value row)
  (last row))

(def (gerbil-ascent-joined-row key value)
  (append key (list value)))

(def (gerbil-ascent-expression-value payload environment)
  (apply (vector-ref payload 1)
         (map (lambda (name)
                (let (binding (assq name environment))
                  (unless binding
                    (error "unbound ASCENT expression variable" name))
                  (cdr binding)))
              (vector-ref payload 0))))

;;; Bind one candidate row without mutating the caller's environment. A
;;; repeated variable or failed pattern rejects this candidate with #f.
;; gerbil-ascent-bind-row
;;   : (-> Terms Row Environment (Maybe Environment))
;;   | doc m%
;;       Match ordered terms against one row and return extended bindings.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-bind-row '((variable . x)) '(3) '())
;;       ;; => an environment binding x to 3
;;       ```
;;     %
(def (gerbil-ascent-bind-row terms row environment)
  (let loop ((patterns terms) (values row) (bindings environment))
    (if (null? patterns)
      bindings
      (let* ((term (car patterns))
             (value (car values))
             (kind (car term)))
        (case kind
          ((wildcard)
           (loop (cdr patterns) (cdr values) bindings))
          ((pattern)
           (let* ((payload (cdr term))
                  (matched ((vector-ref payload 1) value))
                  (outputs (vector-ref payload 0)))
             (and matched
                  (begin
                    (unless (and (list? matched)
                                 (= (length matched) (length outputs)))
                      (error "ASCENT pattern returned invalid bindings"
                             matched outputs))
                    (loop (cdr patterns) (cdr values)
                          (append (map cons outputs matched) bindings))))))
          ((literal expression)
           (and (equal? (if (eq? kind 'literal)
                          (cdr term)
                          (gerbil-ascent-expression-value
                           (cdr term) bindings))
                        value)
                (loop (cdr patterns) (cdr values) bindings)))
          (else
           (let* ((name (cdr term))
                  (previous (assq name bindings)))
             (if previous
               (and (equal? (cdr previous) value)
                    (loop (cdr patterns) (cdr values) bindings))
               (loop (cdr patterns) (cdr values)
                     (cons (cons name value) bindings))))))))))

(def (gerbil-ascent-head-row terms environment)
  (map (lambda (term)
         (case (car term)
           ((literal) (cdr term))
           ((expression)
            (gerbil-ascent-expression-value (cdr term) environment))
           ((pattern)
            (error "ASCENT pattern is invalid in a rule head"))
           ((wildcard)
            (error "ASCENT wildcard is invalid in a rule head"))
           (else
            (let (binding (assq (cdr term) environment))
              (unless binding
                (error "unbound ASCENT head variable" (cdr term)))
              (cdr binding)))))
       terms))

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

(def (gerbil-ascent-dependency-reaches? dependencies from target seen)
  (cond
   ((= from target) #t)
   ((vector-ref seen from) #f)
   (else
    (vector-set! seen from #t)
    (ormap
     (lambda (dependency)
       (and (= (vector-ref dependency 0) from)
            (gerbil-ascent-dependency-reaches?
             dependencies (vector-ref dependency 1) target seen)))
     dependencies))))

(def (gerbil-ascent-cycle-kind dependencies relation-count)
  (ormap
   (lambda (dependency)
     (and (= (vector-ref dependency 2) 1)
          (gerbil-ascent-dependency-reaches?
           dependencies (vector-ref dependency 1)
           (vector-ref dependency 0)
           (make-vector relation-count #f))
          (vector-ref dependency 3)))
   dependencies))

;;; Negative, aggregate, and lattice-to-relation edges require a later
;;; stratum. Relaxation rejects cycles that violate that ordering.
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
        (dependencies []))
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
                            (eq? (vector-ref kinds head-index) 'relation))))
                 (set! dependencies
                   (cons (vector head-index body-index
                                 (if (and (eq? kind 'atom)
                                          (not lattice-projection?))
                                   0 1)
                                 (if lattice-projection?
                                   'lattice-projection kind))
                         dependencies)))))
           (vector-ref rule 1)))
        (vector-ref rule 0)))
     rule-plans)
    (let relax ((pass 0))
      (let (changed? #f)
        (for-each
         (lambda (dependency)
           (let* ((head (vector-ref dependency 0))
                  (body (vector-ref dependency 1))
                  (required (+ (vector-ref strata body)
                               (vector-ref dependency 2))))
             (when (> required (vector-ref strata head))
               (vector-set! strata head required)
               (set! changed? #t))))
         dependencies)
        (when changed?
          (when (>= pass (- relation-count 1))
            (case (gerbil-ascent-cycle-kind dependencies relation-count)
              ((aggregate)
               (error "unstratifiable ASCENT aggregate cycle"))
              ((negation)
               (error "unstratifiable ASCENT negation cycle"))
              ((lattice-projection)
               (error "unstratifiable ASCENT lattice projection cycle"))
              (else
               (error "unstratifiable ASCENT dependency cycle"))))
          (relax (+ pass 1)))))
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
