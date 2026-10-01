;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Bounded, inert rule proposals against a caller-owned snapshot.
;;; A receipt is an observation of one candidate, not source admission.
;;; Inspect inert proposal data, then lower the checked form into the
;;; trusted Scheme relational language. This module never evaluates a
;;; candidate-supplied procedure.
(import (only-in :gerbil-ascent/candidate/types
                 reasoning-snapshot-relations
                 make-reasoning-diagnostic make-candidate-rejection
                 make-reasoning-candidate reasoning-candidate-relations
                 reasoning-candidate-facts reasoning-candidate-rules
                 reasoning-candidate-query reasoning-candidate-limits
                 +max-relations+ +max-rules+ +max-input-facts+
                 +max-derived-facts+ +max-output-facts+)
        (only-in :gerbil-ascent/program/objects
                 gerbil-ascent-relation gerbil-ascent-atom
                 gerbil-ascent-negation gerbil-ascent-rule
                 gerbil-ascent-program gerbil-ascent-variable
                 gerbil-ascent-wildcard gerbil-ascent-literal)
        (only-in :gerbil-ascent/program/scheme-checked
                 relational-where relational-compute relational-reducer))

(export scalar? candidate-variable? candidate-inspect candidate-program
        candidate-planner-path)

(def (scalar? value)
  (or (exact-integer? value) (boolean? value) (symbol? value) (char? value)))

;; : (forall (a) (-> Symbol (List Datum) Datum a))
;;; Rejection exits inspection with a located diagnostic.
(def (reject code path detail)
  (raise
   (make-candidate-rejection
    (make-reasoning-diagnostic code path detail))))

;; : (-> Datum Boolean)
(def (candidate-variable? value)
  (and (symbol? value)
       (let (spelling (symbol->string value))
         (and (> (string-length spelling) 1)
              (char=? (string-ref spelling 0) #\?)))))

(def (candidate-term? value)
  (and (scalar? value)
       (not (eq? value '?))))

;;; Reject syntax objects, vectors, closures and other executable values
;;; before inspection. The depth guard prevents a recursively shaped datum
;;; from consuming unbounded inspector stack before structural budgets apply.
(def (candidate-inert? value fuel)
  (and (> fuel 0)
       (or (scalar? value)
           (and (pair? value)
                (candidate-inert? (car value) (- fuel 1))
                (candidate-inert? (cdr value) (- fuel 1)))
           (null? value))))

;;; Keep the data grammar restricted to fixed, inspectable operations from
;;; the trusted Scheme DSL. No candidate procedure or operator body runs.
;;; Clause indexes survive lowering so a rejected proposal can be revised
;;; without guessing which relation or body atom caused the failure.
(def (candidate-parse datum)
  (unless (and (list? datum) (pair? datum)
               (eq? (car datum) 'candidate)
               (candidate-inert? datum 16384)
               (<= (length (cdr datum)) 256))
    (reject 'invalid-candidate '(candidate) 'expected-inert-candidate-list))
  (let loop ((clauses (cdr datum)) (index 1)
             (relations []) (facts []) (rules [])
             (query #f) (limits #f))
    (if (null? clauses)
      (begin
        (unless query (reject 'missing-query '(query) 'required))
        (unless limits (reject 'missing-limits '(limits) 'required))
        (when (> (length relations) +max-relations+)
          (reject 'relation-limit '(relations) +max-relations+))
        (when (> (length rules) +max-rules+)
          (reject 'rule-limit '(rules) +max-rules+))
        (make-reasoning-candidate
         (reverse relations) (reverse facts) (reverse rules)
         query limits))
      (let ((clause (car clauses))
            (path (list 'clause index)))
        (unless (and (list? clause) (pair? clause)
                     (symbol? (car clause)))
          (reject 'invalid-clause path clause))
        (case (car clause)
          ((relation)
           (unless (and (= (length clause) 3)
                        (symbol? (cadr clause))
                        (exact-integer? (caddr clause))
                        (<= 0 (caddr clause)))
             (reject 'invalid-relation path clause))
           (loop (cdr clauses) (+ index 1)
                 (cons (cons (cadr clause) (caddr clause)) relations)
                 facts rules query limits))
          ((fact)
           (unless (and (>= (length clause) 2)
                        (symbol? (cadr clause))
                        (andmap (lambda (value)
                                  (and (scalar? value)
                                       (not (candidate-variable? value))
                                       (not (eq? value '?))))
                                (cddr clause)))
             (reject 'invalid-fact path clause))
           (loop (cdr clauses) (+ index 1) relations
                 (cons (vector (cadr clause) (cddr clause) index) facts)
                 rules query limits))
          ((rule)
           (unless (>= (length clause) 3)
             (reject 'invalid-rule path clause))
           (loop (cdr clauses) (+ index 1) relations facts
                 (cons (vector (cadr clause) (cddr clause) index) rules)
                 query limits))
          ((query)
           (when query (reject 'duplicate-query path clause))
           (unless (>= (length clause) 2)
             (reject 'invalid-query path clause))
           (loop (cdr clauses) (+ index 1) relations facts rules
                 (vector (cdr clause) index) limits))
          ((limits)
           (when limits (reject 'duplicate-limits path clause))
           (unless (and (= (length clause) 4)
                        (andmap (lambda (value)
                                  (and (exact-integer? value) (> value 0)))
                                (cdr clause))
                        (<= (cadr clause) +max-input-facts+)
                        (<= (caddr clause) +max-derived-facts+)
                        (<= (cadddr clause) +max-output-facts+))
             (reject 'invalid-limits path clause))
           (loop (cdr clauses) (+ index 1) relations facts rules query
                 (cdr clause)))
          (else
           (reject 'unsupported-construct path (car clause))))))))

(def (atom-check atom schema path)
  (unless (and (list? atom) (pair? atom) (symbol? (car atom)))
    (reject 'invalid-atom path atom))
  (let (declaration (assq (car atom) schema))
    (unless declaration
      (reject 'unknown-relation path (car atom)))
    (unless (= (length (cdr atom)) (cdr declaration))
      (reject 'arity-mismatch path (car atom)))
    (for-each
     (lambda (term position)
       (unless (candidate-term? term)
         (reject 'invalid-term (append path (list 'term position)) term)))
     (cdr atom) (iota (length (cdr atom)) 1))))

(def (logic-variable? value)
  (and (candidate-variable? value) (not (eq? value '?_))))

(def (require-bound-inputs inputs bound path)
  (for-each
   (lambda (input position)
     (unless (and (logic-variable? input) (memq input bound))
       (reject 'unbound-operator-input
               (append path (list 'input position)) input)))
   inputs (iota (length inputs) 1)))

(def (checked-operation form mode bound path)
  (unless (and (list? form) (pair? form) (symbol? (car form)))
    (reject 'invalid-operator path form))
  (let ((operation (car form))
        (inputs (cdr form)))
    (unless
     (case mode
       ((where)
        (case operation
          ((even?) (= (length inputs) 1))
          ((<) (= (length inputs) 2))
          (else #f)))
       ((compute)
        (case operation
          ((identity) (= (length inputs) 1))
          ((+) (= (length inputs) 2))
          (else #f)))
       (else #f))
     (reject 'unsupported-operator path form))
    (require-bound-inputs inputs bound path)))

;;; Inspect body clauses in evaluation order. Positive atoms bind variables;
;;; negation and fixed scalar tests only read prior bindings; computation
;;; and reduction add one fresh binding. The planner remains authoritative
;;; for combined dependencies and aggregate stratum requirements.
(def (candidate-check-body-clause clause schema bound path)
  (unless (and (list? clause) (pair? clause) (symbol? (car clause)))
    (reject 'invalid-body-clause path clause))
  (case (car clause)
    ((not)
     (unless (= (length clause) 2)
       (reject 'invalid-negation path clause))
     (let (atom (cadr clause))
       (atom-check atom schema path)
       (for-each
        (lambda (term position)
          (when (and (logic-variable? term) (not (memq term bound)))
            (reject 'unsafe-negation
                    (append path (list 'term position)) term)))
        (cdr atom) (iota (length (cdr atom)) 1)))
     bound)
    ((where)
     (unless (= (length clause) 2)
       (reject 'invalid-filter path clause))
     (checked-operation (cadr clause) 'where bound path)
     bound)
    ((compute)
     (unless (and (= (length clause) 3)
                  (logic-variable? (cadr clause)))
       (reject 'invalid-computation path clause))
     (when (memq (cadr clause) bound)
       (reject 'duplicate-binding path (cadr clause)))
     (checked-operation (caddr clause) 'compute bound path)
     (cons (cadr clause) bound))
    ((reduce)
     (unless (and (= (length clause) 4)
                  (logic-variable? (cadr clause))
                  (list? (caddr clause))
                  (pair? (caddr clause)))
       (reject 'invalid-reduction path clause))
     (when (memq (cadr clause) bound)
       (reject 'duplicate-binding path (cadr clause)))
     (let* ((mode (caaddr clause))
            (inputs (cdaddr clause))
            (atom (cadddr clause)))
       (unless (and (symbol? mode)
                    (case mode
                      ((count) (null? inputs))
                      ((sum min max) (= (length inputs) 1))
                      (else #f))
                    (andmap logic-variable? inputs))
         (reject 'unsupported-reduction path (caddr clause)))
       (atom-check atom schema (append path '(aggregate)))
       (for-each
        (lambda (input)
          (unless (memq input (cdr atom))
            (reject 'reduction-input-absent path input)))
        inputs))
     (cons (cadr clause) bound))
    (else
     (atom-check clause schema path)
     (foldl
      (lambda (term prior)
        (if (logic-variable? term) (cons term prior) prior))
      bound (cdr clause)))))

;;; Inspection must resolve every symbol against the copied source schema
;;; before a planner sees the proposal. Only source names accept candidate
;;; facts; a rule may write only a newly declared derived relation.
;; : (-> ReasoningSnapshot Datum ReasoningCandidate)
(def (candidate-inspect snapshot candidate)
  (let* ((spec (candidate-parse candidate))
         (source (reasoning-snapshot-relations snapshot))
         (source-schema
          (map (lambda (entry) (cons (car entry) (cadr entry))) source))
         (derived (reasoning-candidate-relations spec))
         (schema (append source-schema derived))
         (seen (map car source-schema)))
    (for-each
     (lambda (entry)
       (when (memq (car entry) seen)
         (reject 'duplicate-relation '(relations) (car entry)))
       (set! seen (cons (car entry) seen)))
     derived)
    (for-each
     (lambda (fact)
       (let ((name (vector-ref fact 0))
             (row (vector-ref fact 1))
             (path (list 'clause (vector-ref fact 2))))
         (let (declaration (assq name source-schema))
           (unless declaration
             (reject 'fact-needs-source path name))
           (unless (= (length row) (cdr declaration))
             (reject 'arity-mismatch path name)))))
     (reasoning-candidate-facts spec))
    (for-each
     (lambda (rule)
       (let* ((head (vector-ref rule 0))
              (body (vector-ref rule 1))
              (path (list 'clause (vector-ref rule 2)))
              (bound []))
         (atom-check head schema (append path '(head)))
         (unless (assq (car head) derived)
           (reject 'rule-writes-source (append path '(head)) (car head)))
         (for-each
          (lambda (clause position)
            (set! bound
              (candidate-check-body-clause
               clause schema bound (append path (list 'body position)))))
          body (iota (length body) 1))
         (for-each
          (lambda (term position)
            (cond
             ((eq? term '?_)
              (reject 'wildcard-head
                      (append path (list 'head 'term position)) term))
             ((and (candidate-variable? term)
                   (not (memq term bound)))
              (reject 'unbound-head-variable
                      (append path (list 'head 'term position)) term))))
          (cdr head) (iota (length (cdr head)) 1))))
     (reasoning-candidate-rules spec))
    (let* ((query (vector-ref (reasoning-candidate-query spec) 0))
           (path (list 'clause
                       (vector-ref (reasoning-candidate-query spec) 1))))
      (atom-check query schema path))
    (let ((source-count
           (apply + (map (lambda (entry) (length (caddr entry))) source)))
          (candidate-count (length (reasoning-candidate-facts spec))))
      (when (> (+ source-count candidate-count)
               (car (reasoning-candidate-limits spec)))
        (reject 'input-budget '(limits input) (+ source-count candidate-count))))
    spec))

(def (candidate-term->object term)
  (cond
   ((eq? term '?_) (gerbil-ascent-wildcard))
   ((candidate-variable? term) (gerbil-ascent-variable term))
   (else (gerbil-ascent-literal term))))

(def (candidate-atom->object atom)
  (gerbil-ascent-atom
   (car atom) (map candidate-term->object (cdr atom))))

(def (candidate-body->object clause)
  (case (car clause)
    ((not)
     (let (atom (cadr clause))
       (gerbil-ascent-negation
        (car atom) (map candidate-term->object (cdr atom)))))
    ((where)
     (relational-where (caadr clause) (cdadr clause)))
    ((compute)
     (relational-compute
      (cadr clause) (caaddr clause) (cdaddr clause)))
    ((reduce)
     (let ((operator (caddr clause))
           (atom (cadddr clause)))
       (relational-reducer
        (cadr clause) (car operator) (cdr operator)
        (car atom) (map candidate-term->object (cdr atom)))))
    (else (candidate-atom->object clause))))

;;; Lower the checked data into POO declarations with no caller procedures.
;;; The source-handle list marks only copied inputs as replaceable; derived
;;; relations remain private to this one attempt.
;; : (-> ReasoningSnapshot ReasoningCandidate RelationalProgram)
(def (candidate-program snapshot spec)
  (let* ((source (reasoning-snapshot-relations snapshot))
         (facts (reasoning-candidate-facts spec))
         (derived (reasoning-candidate-relations spec))
         (source-relations
          (map (lambda (entry)
                 (let (name (car entry))
                   (gerbil-ascent-relation
                    name (cadr entry)
                    (append (caddr entry)
                            (map (lambda (fact) (vector-ref fact 1))
                                 (filter (lambda (fact)
                                           (eq? (vector-ref fact 0) name))
                                         facts))))))
               source))
         (derived-relations
          (map (lambda (entry)
                 (gerbil-ascent-relation (car entry) (cdr entry) []))
               derived))
         (relations (append source-relations derived-relations))
         (rules
          (map (lambda (rule)
                 (gerbil-ascent-rule
                  (list (candidate-atom->object (vector-ref rule 0)))
                  (map candidate-body->object (vector-ref rule 1))))
               (reasoning-candidate-rules spec)))
         (limits (reasoning-candidate-limits spec)))
    (gerbil-ascent-program
     relations rules (car limits) (cadr limits) (caddr limits)
     (map car source))))

;;; Planner positions are zero-based in the lowered rule list. Map them
;;; back to the candidate's one-based source-clause and body positions.
(def (candidate-planner-path spec path)
  (if (and (list? path) (= (length path) 4)
           (eq? (car path) 'rule)
           (exact-integer? (cadr path))
           (<= 0 (cadr path))
           (< (cadr path) (length (reasoning-candidate-rules spec)))
           (memq (caddr path) '(body head))
           (exact-integer? (cadddr path)))
    (list 'clause
          (vector-ref
           (list-ref (reasoning-candidate-rules spec) (cadr path)) 2)
          (caddr path) (+ 1 (cadddr path)))
    path))
