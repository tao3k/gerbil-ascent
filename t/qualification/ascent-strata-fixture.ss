;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Frozen relaxation oracle from commit 74f0046. Qualification and matched
;;; planning benchmarks use it; runtime evaluation uses core/rule-semantics.ss.
(export ascent-reference-rule-strata ascent-strata-rule-plans)

(def (ascent-strata-rule-plans edges)
  (map (lambda (edge)
         (vector (list (vector (vector-ref edge 0) []))
                 (list (vector (vector-ref edge 2)
                               (vector (vector-ref edge 1) [])))))
       edges))

(def (ascent-reference-dependency-reaches? dependencies from target seen)
  (cond
   ((= from target) #t)
   ((vector-ref seen from) #f)
   (else
    (vector-set! seen from #t)
    (ormap
     (lambda (dependency)
       (and (= (vector-ref dependency 0) from)
            (ascent-reference-dependency-reaches?
             dependencies (vector-ref dependency 1) target seen)))
     dependencies))))

(def (ascent-reference-cycle-kind dependencies relation-count)
  (ormap
   (lambda (dependency)
     (and (= (vector-ref dependency 2) 1)
          (ascent-reference-dependency-reaches?
           dependencies (vector-ref dependency 1)
           (vector-ref dependency 0)
           (make-vector relation-count #f))
          (vector-ref dependency 3)))
   dependencies))

;;; Negative, aggregate, and lattice-to-relation edges require a later
;;; stratum. Relaxation rejects cycles that violate that ordering.
;; ascent-reference-rule-strata
;;   : (-> RulePlans Nat RelationKinds Strata)
;;   | doc m%
;;       Assign the minimum valid stratum to each declared relation.
;;
;;       # Examples
;;
;;       ```scheme
;;       (ascent-reference-rule-strata '() 1 '#(relation))
;;       ;; => a vector containing stratum 0
;;       ```
;;     %
(def (ascent-reference-rule-strata rule-plans relation-count kinds)
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
            (case (ascent-reference-cycle-kind dependencies relation-count)
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

