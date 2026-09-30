;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Bounded, inert positive-rule proposals against a caller-owned snapshot.
;;; A receipt is an observation of one candidate, not source admission.
(import (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :std/error exception->string)
        (only-in :gerbil-ascent/program/objects
                 gerbil-ascent-relation gerbil-ascent-atom
                 gerbil-ascent-rule gerbil-ascent-program
                 gerbil-ascent-variable gerbil-ascent-wildcard
                 gerbil-ascent-literal)
        (only-in :gerbil-ascent/program/scheme-language
                 relational-admit relational-solve relational-query-name))

(export reasoning-source-snapshot reasoning-attempt
        reasoning-snapshot? reasoning-snapshot-identity
        reasoning-snapshot-generation reasoning-snapshot-digest
        reasoning-receipt? reasoning-receipt-status
        reasoning-receipt-snapshot-identity
        reasoning-receipt-snapshot-generation
        reasoning-receipt-snapshot-digest
        reasoning-receipt-candidate-digest
        reasoning-receipt-query reasoning-receipt-rows
        reasoning-receipt-diagnostics reasoning-receipt-evidence
        reasoning-diagnostic? reasoning-diagnostic-code
        reasoning-diagnostic-path reasoning-diagnostic-detail
        reasoning-evidence? reasoning-evidence-kind
        reasoning-evidence-support reasoning-evidence-reachable)

(defstruct reasoning-snapshot (identity generation digest relations))
(defstruct reasoning-diagnostic (code path detail))
(defstruct reasoning-receipt
  (status snapshot-identity snapshot-generation snapshot-digest
          candidate-digest query rows diagnostics evidence))
(defstruct reasoning-evidence (kind support reachable))
(defstruct reasoning-candidate (relations facts rules query limits))
(defstruct candidate-rejection (diagnostic))

(def +max-relations+ 64)
(def +max-rules+ 64)
(def +max-input-facts+ 1024)
(def +max-derived-facts+ 4096)
(def +max-output-facts+ 4096)

(def (scalar? value)
  (or (exact-integer? value) (boolean? value) (symbol? value) (char? value)))

(def (copy-row row arity)
  (and (list? row) (= (length row) arity)
       (andmap scalar? row)
       (map identity row)))

;;; Candidate rows may be caller-owned pairs. Copy nested pairs at the
;;; receipt boundary so later edits to a proposal cannot rewrite evidence.
(def (copy-datum datum)
  (if (pair? datum)
    (cons (copy-datum (car datum)) (copy-datum (cdr datum)))
    datum))

(def (digest-datum datum)
  (hex-encode
   (sha256
    (string->utf8
     (call-with-output-string ""
       (lambda (port) (write datum port)))))))

;;; The caller supplies identity and generation. The digest binds their
;;; contents for this local receipt; it does not certify source authority.
;; reasoning-source-snapshot
;;   : (-> (U Symbol String) Nat (List SourceDeclaration) ReasoningSnapshot)
;;   | doc m%
;;       Copy finite scalar source rows into a generation-labelled snapshot.
;;       The resulting digest detects a changed local snapshot but does not
;;       authenticate the caller or grant admission authority.
;;
;;       # Examples
;;
;;       ```scheme
;;       (reasoning-source-snapshot 'graph 1 '((edge 2 ((1 2)))))
;;       ;; => a copied source snapshot with one edge
;;       ```
;;     %
(def (reasoning-source-snapshot identity generation declarations)
  (unless (and (or (symbol? identity) (string? identity))
               (exact-integer? generation) (<= 0 generation)
               (list? declarations)
               (<= (length declarations) +max-relations+))
    (error "invalid reasoning source snapshot"))
  (let loop ((remaining declarations) (seen []) (copied []) (facts 0))
    (if (null? remaining)
      (let (relations (reverse copied))
        (make-reasoning-snapshot
         identity generation
         (digest-datum (list 'reasoning-snapshot-v1 identity
                             generation relations))
         relations))
      (let (entry (car remaining))
        (unless (and (list? entry) (= (length entry) 3)
                     (symbol? (car entry))
                     (exact-integer? (cadr entry))
                     (<= 0 (cadr entry))
                     (list? (caddr entry))
                     (not (memq (car entry) seen)))
          (error "invalid or duplicate reasoning source declaration" entry))
        (let* ((name (car entry))
               (arity (cadr entry))
               (rows (caddr entry))
               (next-facts (+ facts (length rows))))
          (when (> next-facts +max-input-facts+)
            (error "reasoning source snapshot exceeds input cap"))
          (let (owned
                (map (lambda (row)
                       (or (copy-row row arity)
                           (error "invalid reasoning source row" name row)))
                     rows))
            (loop (cdr remaining) (cons name seen)
                  (cons (list name arity owned) copied)
                  next-facts)))))))

(def (reject code path detail)
  (raise
   (make-candidate-rejection
    (make-reasoning-diagnostic code path detail))))

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

;;; Keep the data grammar deliberately smaller than the trusted Scheme DSL.
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

;;; Inspection must resolve every symbol against the copied source schema
;;; before a planner sees the proposal. Only source names accept candidate
;;; facts; a rule may write only a newly declared derived relation.
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
          (lambda (atom position)
            (atom-check atom schema (append path (list 'body position)))
            (for-each
             (lambda (term)
               (when (and (candidate-variable? term)
                          (not (eq? term '?_)))
                 (set! bound (cons term bound))))
             (cdr atom)))
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

;;; Lower the checked data into POO declarations with no caller procedures.
;;; The source-handle list marks only copied inputs as replaceable; derived
;;; relations remain private to this one attempt.
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
                  (map candidate-atom->object (vector-ref rule 1))))
               (reasoning-candidate-rules spec)))
         (limits (reasoning-candidate-limits spec)))
    (gerbil-ascent-program
     relations rules (car limits) (cadr limits) (caddr limits)
     (map car source))))

(def (query-row-matches? terms row)
  (let loop ((terms terms) (values row) (bindings []))
    (if (null? terms)
      #t
      (let ((term (car terms)) (value (car values)))
        (cond
         ((eq? term '?_)
          (loop (cdr terms) (cdr values) bindings))
         ((candidate-variable? term)
          (let (binding (assq term bindings))
            (if binding
              (and (equal? (cdr binding) value)
                   (loop (cdr terms) (cdr values) bindings))
              (loop (cdr terms) (cdr values)
                    (cons (cons term value) bindings)))))
         (else
          (and (equal? term value)
               (loop (cdr terms) (cdr values) bindings))))))))

;;; A generic recursive rule can have a complete answer without graph-path
;;; provenance. Recognize only the exact rule pair used by the graph witness
;;; checker; a near-miss join must never inherit that proof interpretation.
(def (candidate-graph-case? snapshot spec query)
  (let ((source (reasoning-snapshot-relations snapshot))
        (derived (reasoning-candidate-relations spec))
        (rules (reasoning-candidate-rules spec)))
    (and (= (length source) 1)
         (eq? (caar source) 'edge)
         (= (cadar source) 2)
         (equal? derived '((path . 2)))
         (= (length rules) 2)
         (let (forms
               (map (lambda (rule)
                      (cons (vector-ref rule 0) (vector-ref rule 1)))
                    rules))
           (and (member '((path ?x ?y) (edge ?x ?y)) forms)
                (member '((path ?x ?z) (path ?x ?y) (edge ?y ?z))
                        forms)))
         (= (length query) 3)
         (eq? (car query) 'path)
         (exact-integer? (cadr query))
         (exact-integer? (caddr query)))))

(def (candidate-edge-records snapshot spec)
  (append
   (map (lambda (row index) (list 'source index row))
        (caddar (reasoning-snapshot-relations snapshot))
        (iota (length (caddar (reasoning-snapshot-relations snapshot))) 1))
   (map (lambda (fact)
          (list 'candidate (vector-ref fact 2) (vector-ref fact 1)))
        (reasoning-candidate-facts spec))))

;;; Breadth-first search yields one shortest support and the reachable cut.
;;; Candidate edges remain labelled as hypothetical in the returned support.
(def (candidate-graph-walk records origin target)
  (let ((visited (make-hash-table))
        (reachable (list origin))
        (support #f))
    (hash-put! visited origin #t)
    (let loop ((front (list (cons origin []))) (back []))
      (cond
       ((null? front)
        (if (null? back)
          (values support (reverse reachable))
          (loop (reverse back) [])))
       (else
        (let* ((state (car front))
               (node (car state))
               (path (cdr state))
               (next back))
          (for-each
           (lambda (record)
             (let (edge (caddr record))
               (when (equal? (car edge) node)
                 (let ((neighbor (cadr edge))
                       (extended (cons record path)))
                   (when (and (not support) (equal? neighbor target))
                     (set! support (reverse extended)))
                   (unless (hash-get visited neighbor)
                     (hash-put! visited neighbor #t)
                     (set! reachable (cons neighbor reachable))
                     (set! next (cons (cons neighbor extended) next)))))))
           records)
          (loop (cdr front) next)))))))

;;; Evidence is deliberately narrower than query execution: only the exact
;;; two-rule graph closure receives a path or cut. Other valid programs
;;; return complete rows with an unsupported evidence kind.
(def (candidate-evidence snapshot spec query rows)
  (if (candidate-graph-case? snapshot spec query)
    (let-values (((support reachable)
                  (candidate-graph-walk
                   (candidate-edge-records snapshot spec)
                   (cadr query) (caddr query))))
      (cond
       ((and (pair? rows) support)
        (make-reasoning-evidence 'witness support []))
       ((and (null? rows) (not support)
             (not (member (caddr query) reachable)))
        (make-reasoning-evidence 'cut [] reachable))
       ((and (null? rows) (not support)
             (equal? (cadr query) (caddr query)))
        (make-reasoning-evidence 'unsupported [] []))
       (else #f)))
    (make-reasoning-evidence 'unsupported [] [])))

;;; Detach lists from the submitted candidate and from engine output.
;;; Accessors still return ordinary Scheme values; callers own mutations.
(def (reasoning-receipt-for snapshot digest status query rows
                            diagnostics evidence)
  (make-reasoning-receipt
   status
   (reasoning-snapshot-identity snapshot)
   (reasoning-snapshot-generation snapshot)
   (reasoning-snapshot-digest snapshot)
   digest (copy-datum query) (copy-datum rows)
   (map (lambda (diagnostic)
          (make-reasoning-diagnostic
           (reasoning-diagnostic-code diagnostic)
           (copy-datum (reasoning-diagnostic-path diagnostic))
           (copy-datum (reasoning-diagnostic-detail diagnostic))))
        diagnostics)
   (and evidence
        (make-reasoning-evidence
         (reasoning-evidence-kind evidence)
         (copy-datum (reasoning-evidence-support evidence))
         (copy-datum (reasoning-evidence-reachable evidence))))))

(def (capture thunk)
  (with-catch
   (lambda (failure) (vector #f failure))
   (lambda () (vector #t (thunk)))))

(def (failure-detail failure)
  (let (message (exception->string failure))
    (if (> (string-length message) 240)
      (substring message 0 240)
      message)))

;; reasoning-attempt
;;   : (-> ReasoningSnapshot InertCandidate ReasoningReceipt)
;;   | doc m%
;;       Inspect a bounded, positive candidate as data, run it against one
;;       copied source snapshot, and return a complete/rejected/unknown
;;       observation. The receipt cannot promote candidate facts to source.
;;
;;       # Examples
;;
;;       ```scheme
;;       (reasoning-attempt snapshot
;;         '(candidate (relation path 2)
;;                     (rule (path ?x ?y) (edge ?x ?y))
;;                     (query path 1 2) (limits 8 8 16)))
;;       ;; => a receipt with status complete or a located rejection
;;       ```
;;     %
;;; Boundary: Structural diagnostics use candidate clause indexes, not
;;; Scheme syntax locations; planner failures retain their own messages.
(def (reasoning-attempt snapshot candidate)
  (unless (reasoning-snapshot? snapshot)
    (error "reasoning attempt requires a source snapshot" snapshot))
  (let (inspection (capture (lambda () (candidate-inspect snapshot candidate))))
    (if (not (vector-ref inspection 0))
      (let (failure (vector-ref inspection 1))
        (if (candidate-rejection? failure)
          (reasoning-receipt-for
           snapshot #f 'rejected #f []
           (list (candidate-rejection-diagnostic failure)) #f)
          (reasoning-receipt-for
           snapshot #f 'unknown #f []
           (list (make-reasoning-diagnostic
                  'inspector-failed '(candidate)
                  (failure-detail failure))) #f)))
      (let* ((spec (vector-ref inspection 1))
             (digest (digest-datum (list 'reasoning-candidate-v1 candidate)))
             (query (vector-ref (reasoning-candidate-query spec) 0))
             (prepared
              (capture
               (lambda ()
                 (relational-admit
                  (candidate-program snapshot spec))))))
        (if (not (vector-ref prepared 0))
          (reasoning-receipt-for
           snapshot digest 'rejected query []
           (list (make-reasoning-diagnostic
                  'planner-rejected '(program)
                  (failure-detail (vector-ref prepared 1)))) #f)
          (let (solved
                (capture
                 (lambda ()
                   (relational-solve
                    (vector-ref prepared 1)))))
            (if (not (vector-ref solved 0))
              (reasoning-receipt-for
               snapshot digest 'unknown query []
               (list (make-reasoning-diagnostic
                      'solve-failed '(solve)
                      (failure-detail (vector-ref solved 1)))) #f)
              (let (observed
                    (capture
                     (lambda ()
                       (let* ((all
                               (relational-query-name
                                (vector-ref solved 1) (car query)))
                              (rows
                               (filter (lambda (row)
                                         (query-row-matches? (cdr query) row))
                                       all)))
                         (vector rows
                                 (candidate-evidence
                                  snapshot spec query rows))))))
                (cond
                 ((not (vector-ref observed 0))
                  (reasoning-receipt-for
                   snapshot digest 'unknown query []
                   (list (make-reasoning-diagnostic
                          'query-failed '(query)
                          (failure-detail (vector-ref observed 1)))) #f))
                 ((vector-ref (vector-ref observed 1) 1)
                  (reasoning-receipt-for
                   snapshot digest 'complete query
                   (vector-ref (vector-ref observed 1) 0) []
                   (vector-ref (vector-ref observed 1) 1)))
                 (else
                  (reasoning-receipt-for
                   snapshot digest 'unknown query []
                   (list (make-reasoning-diagnostic
                          'evidence-mismatch '(explain) query)) #f)))))))))))
