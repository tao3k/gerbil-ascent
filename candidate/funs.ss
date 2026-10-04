;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Pure operations over inspected candidate data. The native planner uses
;;; core/rule-semantics.ss over its different, lowered rule representation.
(import (only-in :gerbil-ascent/candidate/types
                 reasoning-snapshot-relations reasoning-candidate-relations)
        (only-in :gerbil-ascent/candidate/program candidate-variable?))

(export candidate-copy-pairs candidate-same-row-set?
        candidate-schema-of candidate-required-entry
        candidate-bind-atom candidate-fixed-clause candidate-strata-of)

;; Copy only the pair spine. Inspected candidate leaves are scalars.
(def (candidate-copy-pairs datum)
  (if (pair? datum)
    (cons (candidate-copy-pairs (car datum))
          (candidate-copy-pairs (cdr datum)))
    datum))

(def (candidate-same-row-set? left right)
  (and (= (length left) (length right))
       (andmap (lambda (row) (and (member row right) #t)) left)
       (andmap (lambda (row) (and (member row left) #t)) right)))

(def (candidate-schema-of snapshot spec)
  (append
   (map (lambda (entry) (cons (car entry) (cadr entry)))
        (reasoning-snapshot-relations snapshot))
   (reasoning-candidate-relations spec)))

(def (candidate-required-entry name index)
  (or (assq name index)
      (error "candidate is missing inspected entry" name)))

;; A failed match returns #f; bindings are never changed in place.
;; candidate-bind-atom
;;   : (forall (a) (-> (Atom a) (Row a) (Bindings a) (Maybe (Bindings a))))
;;   : (-> Atom Row Bindings (Maybe Bindings))
;;   | doc m%
;;       Extend an inspected candidate environment for one relation row.
;;       Repeated variables must agree; wildcard does not bind.
;;
;;       # Examples
;;
;;       ```scheme
;;       (candidate-bind-atom '(edge ?x ?x) '(2 2) '())
;;       ;; => ((?x . 2))
;;       ```
;;     %
(def (candidate-bind-atom atom row prior)
  (let loop ((terms (cdr atom)) (values row) (bindings prior))
    (if (null? terms)
      bindings
      (let ((term (car terms)) (value (car values)))
        (cond
         ((eq? term '?_) (loop (cdr terms) (cdr values) bindings))
         ((candidate-variable? term)
          (let (old (assq term bindings))
            (if old
              (and (equal? (cdr old) value)
                   (loop (cdr terms) (cdr values) bindings))
              (loop (cdr terms) (cdr values)
                    (cons (cons term value) bindings)))))
         (else
          (and (equal? term value)
               (loop (cdr terms) (cdr values) bindings))))))))

;; Re-evaluate the inspected fixed scalar operation, never candidate code.
;; candidate-fixed-clause
;;   : (forall (a) (-> (FixedClause a) (Bindings a) (Maybe (Bindings a))))
;;   : (-> FixedClause Bindings (Maybe Bindings))
;;   | doc m%
;;       Execute one checked filter or scalar computation over bindings.
;;       The inspected form chooses from fixed operations only.
;;
;;       # Examples
;;
;;       ```scheme
;;       (candidate-fixed-clause '(where (even? ?x)) '((?x . 2)))
;;       ;; => ((?x . 2))
;;       ```
;;     %
(def (candidate-fixed-clause clause bindings)
  (let* ((mode (car clause))
         (form (if (eq? mode 'where) (cadr clause) (caddr clause)))
         (inputs (map (lambda (name) (assq name bindings)) (cdr form))))
    (and (andmap (lambda (input) (and input #t)) inputs)
         (let (values (map cdr inputs))
           (case mode
             ((where)
              (case (car form)
                ((even?) (and (exact-integer? (car values))
                              (even? (car values)) bindings))
                ((<) (and (andmap exact-integer? values)
                          (< (car values) (cadr values)) bindings))
                (else #f)))
             ((compute)
              (and (not (assq (cadr clause) bindings))
                   (case (car form)
                     ((identity)
                      (cons (cons (cadr clause) (car values)) bindings))
                     ((+)
                      (and (andmap exact-integer? values)
                           (cons (cons (cadr clause)
                                       (+ (car values) (cadr values)))
                                 bindings)))
                     (else #f))))
             (else #f))))))

;; Positive reads stay in a stratum. Negation and reduction require a
;; strictly lower stratum; a strict cycle has no valid finite replay.
;; candidate-strata-of
;;   : (forall (r) (-> (Schema r) (Rules r) (Maybe (Strata r))))
;;   : (-> Schema Rules (Maybe Strata))
;;   | doc m%
;;       Relax inspected dependencies until stable. Return #f when a strict
;;       cycle makes the finite program unstratifiable.
;;
;;       # Examples
;;
;;       ```scheme
;;       (candidate-strata-of '((edge . 2)) '())
;;       ;; => ((edge . 0))
;;       ```
;;     %
(def (candidate-strata-of schema rules)
  (let (levels (map (lambda (entry) (cons (car entry) 0)) schema))
    (let loop ((round 0))
      (let (changed? #f)
        (for-each
         (lambda (rule)
           (let (head (car (vector-ref rule 0)))
             (for-each
              (lambda (clause)
                (let (dependency
                      (case (car clause)
                        ((not) (cons (caadr clause) 1))
                        ((reduce) (cons (car (cadddr clause)) 1))
                        ((where compute) #f)
                        (else (cons (car clause) 0))))
                  (when dependency
                    (let* ((head-level (candidate-required-entry head levels))
                           (dep-level
                            (candidate-required-entry (car dependency) levels))
                           (required (+ (cdr dep-level) (cdr dependency))))
                      (when (< (cdr head-level) required)
                        (set-cdr! head-level required)
                        (set! changed? #t))))))
              (vector-ref rule 1))))
         rules)
        (cond
         ((not changed?) levels)
         ((>= round (length schema)) #f)
         (else (loop (+ round 1))))))))
