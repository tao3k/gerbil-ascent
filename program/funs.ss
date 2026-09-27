;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Pure planning over private lowered rule vectors. These functions do not
;;; retain relation state and are shared by the serial execution path.
(export gerbil-ascent-rule-strata
        gerbil-ascent-delta-positions
        gerbil-ascent-lattice-key
        gerbil-ascent-lattice-value
        gerbil-ascent-joined-row
        gerbil-ascent-expression-value
        gerbil-ascent-bind-row
        gerbil-ascent-head-row)

(def (gerbil-ascent-lattice-key row)
  (reverse (cdr (reverse row))))

(def (gerbil-ascent-lattice-value row)
  (car (reverse row)))

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

(def (gerbil-ascent-bind-row terms row environment)
  (let loop ((patterns terms) (values row) (bindings environment))
    (if (null? patterns)
      bindings
      (let* ((term (car patterns))
             (value (car values))
             (kind (car term)))
        (case kind
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
           (else
            (let (binding (assq (cdr term) environment))
              (unless binding
                (error "unbound ASCENT head variable" (cdr term)))
              (cdr binding)))))
       terms))

(def (gerbil-ascent-rule-strata rule-plans relation-count)
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
               (let (body-atom (vector-ref clause 1))
                 (set! dependencies
                   (cons (vector (vector-ref head 0)
                                 (vector-ref body-atom 0)
                                 (if (memq (vector-ref clause 0)
                                           '(negation aggregate))
                                   1 0))
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
            (error "unstratifiable ASCENT negation cycle"))
          (relax (+ pass 1)))))
    strata))

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
