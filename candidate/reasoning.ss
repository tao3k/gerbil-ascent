;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Bounded, inert rule proposals against a caller-owned snapshot.
;;; A receipt is an observation of one candidate, not source admission.
(import (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :std/error exception->string)
        (only-in :gerbil-ascent/candidate/types
                 make-reasoning-snapshot reasoning-snapshot?
                 reasoning-snapshot-identity reasoning-snapshot-generation
                 reasoning-snapshot-digest reasoning-snapshot-relations
                 reasoning-snapshot-content-digest reasoning-snapshot-valid?
                 make-reasoning-diagnostic reasoning-diagnostic?
                 reasoning-diagnostic-code reasoning-diagnostic-path
                 reasoning-diagnostic-detail
                 reasoning-candidate-relations reasoning-candidate-facts
                 reasoning-candidate-rules reasoning-candidate-query
                 candidate-rejection? candidate-rejection-diagnostic
                 +max-relations+ +max-input-facts+)
        (only-in :gerbil-ascent/candidate/program
                 scalar? candidate-variable? candidate-inspect candidate-program
                 candidate-planner-path)
        (only-in :gerbil-ascent/candidate/provenance
                 candidate-positive-proof)
        (only-in :gerbil-ascent/candidate/nonmembership
                 candidate-positive-nonmembership)
        (only-in :gerbil-ascent/program/scheme-language
                 relational-admit/report
                 relational-admission-report-admission
                 relational-admission-report-diagnostic
                 relational-diagnostic-code relational-diagnostic-path
                 relational-diagnostic-detail
                 relational-solve relational-query-name))

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
        reasoning-receipt-proof reasoning-receipt-nonmembership
        reasoning-diagnostic? reasoning-diagnostic-code
        reasoning-diagnostic-path reasoning-diagnostic-detail
        reasoning-evidence? reasoning-evidence-kind
        reasoning-evidence-support reasoning-evidence-reachable)

(defstruct reasoning-receipt
  (status snapshot-identity snapshot-generation snapshot-digest
          candidate-digest query rows diagnostics evidence proof
          nonmembership))
(defstruct reasoning-evidence (kind support reachable))

(def (copy-row row arity)
  (and (list? row) (= (length row) arity)
       (andmap scalar? row)
       (map identity row)))

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
         (reasoning-snapshot-content-digest
          identity generation relations)
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
                            diagnostics evidence (proof #f)
                            (nonmembership #f))
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
         (copy-datum (reasoning-evidence-reachable evidence))))
   proof nonmembership))

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
;;   : (-> ReasoningSnapshot InertCandidate [Nat] ReasoningReceipt)
;;   | doc m%
;;       Inspect a bounded candidate as data, run it against one
;;       copied source snapshot, and return a complete/rejected/unknown
;;       observation. The receipt cannot promote candidate facts to source.
;;       The optional third argument caps positive-proof body-row probes;
;;       native query completion, Why proof and ground Why-Not certificate
;;       statuses remain independent.
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
(def (reasoning-attempt snapshot candidate (proof-steps 100000))
  (unless (reasoning-snapshot-valid? snapshot)
    (error "reasoning attempt requires a current valid source snapshot"
           snapshot))
  (unless (and (exact-integer? proof-steps) (> proof-steps 0))
    (error "reasoning attempt requires positive proof work budget"
           proof-steps))
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
                 (relational-admit/report
                  (candidate-program snapshot spec))))))
        (if (not (vector-ref prepared 0))
          (reasoning-receipt-for
           snapshot digest 'rejected query []
           (list (make-reasoning-diagnostic
                  'planner-rejected '(program)
                  (failure-detail (vector-ref prepared 1)))) #f)
          (let ((report (vector-ref prepared 1)))
            (if (relational-admission-report-diagnostic report)
              (let (diagnostic
                    (relational-admission-report-diagnostic report))
                (reasoning-receipt-for
                 snapshot digest 'rejected query []
                 (list
                  (make-reasoning-diagnostic
                   (relational-diagnostic-code diagnostic)
                   (candidate-planner-path
                    spec (relational-diagnostic-path diagnostic))
                   (relational-diagnostic-detail diagnostic))) #f))
              (let (solved
                (capture
                 (lambda ()
                   (relational-solve
                    (relational-admission-report-admission report)))))
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
                  (let* ((rows (vector-ref (vector-ref observed 1) 0))
                         (proof-result
                          (capture
                           (lambda ()
                             (candidate-positive-proof
                              snapshot spec digest 'complete rows
                              proof-steps))))
                         (absence-result
                          (capture
                           (lambda ()
                             (candidate-positive-nonmembership
                              snapshot spec digest 'complete rows
                              proof-steps))))
                         (proof-ok? (vector-ref proof-result 0))
                         (absence-ok? (vector-ref absence-result 0)))
                    (reasoning-receipt-for
                     snapshot digest 'complete query rows
                     (append
                      (if proof-ok? []
                        (list (make-reasoning-diagnostic
                               'proof-failed '(explain)
                               (failure-detail
                                (vector-ref proof-result 1)))))
                      (if absence-ok? []
                        (list (make-reasoning-diagnostic
                               'nonmembership-failed '(explain)
                               (failure-detail
                                (vector-ref absence-result 1))))))
                     (vector-ref (vector-ref observed 1) 1)
                     (and proof-ok? (vector-ref proof-result 1))
                     (and absence-ok? (vector-ref absence-result 1)))))
                 (else
                  (reasoning-receipt-for
                   snapshot digest 'unknown query []
                   (list (make-reasoning-diagnostic
                          'evidence-mismatch '(explain) query)) #f)))))))))))))
