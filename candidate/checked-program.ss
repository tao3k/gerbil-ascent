;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Bounded, inert rule proposals against a caller-owned snapshot.
;;; A receipt is an observation of one candidate, not source admission.
(import (only-in :gerbil-ascent/candidate/datum reasoning-bounded-data? candidate-copy-pairs)
        (only-in :std/crypto/digest sha256)
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
        (only-in :gerbil-ascent/candidate/finite-evidence
                 candidate-finite-evidence candidate-verify-finite-evidence
                 finite-evidence-status)
        (only-in :gerbil-ascent/candidate/stratified-producer
                 candidate-produce-stratified-proof)
        (only-in :gerbil-ascent/candidate/stratified-proof
                 candidate-verify-stratified-proof)
        (only-in :gerbil-ascent/program/scheme-language
                 relational-admit/report
                 relational-admission-report-admission
                 relational-admission-report-diagnostic
                 relational-diagnostic-code relational-diagnostic-path
                 relational-diagnostic-detail
                 relational-solve relational-query-name))

(export candidate-content-digest reasoning-source-snapshot reasoning-attempt
        reasoning-verify-finite-receipt
        reasoning-verify-stratified-receipt
        reasoning-receipt-bound?
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
        reasoning-receipt-stratified
        reasoning-stratified-evidence?
        reasoning-stratified-evidence-status
        reasoning-stratified-evidence-finite
        reasoning-stratified-evidence-proof
        reasoning-stratified-evidence-work-budget
        reasoning-diagnostic? reasoning-diagnostic-code
        reasoning-diagnostic-path reasoning-diagnostic-detail
        reasoning-evidence? reasoning-evidence-kind
        reasoning-evidence-support reasoning-evidence-reachable)

(defstruct reasoning-receipt
  (status snapshot-identity snapshot-generation snapshot-digest
          candidate-digest query rows diagnostics evidence proof
          nonmembership stratified))
(defstruct reasoning-evidence (kind support reachable))
(defstruct reasoning-stratified-evidence (status finite proof work-budget))

(def (copy-row row arity)
  (and (list? row) (= (length row) arity)
       (andmap scalar? row)
       (map identity row)))

(def (digest-datum datum)
  (hex-encode
   (sha256
    (string->utf8
     (call-with-output-string ""
       (lambda (port) (write datum port)))))))

;;; A malformed cyclic or executable proposal has no safe content digest.
;;; Well-formed inert proposals keep the same digest across rejected and
;;; completed attempts, so feedback can be tied to the submitted content.
(def (candidate-content-digest candidate)
  (and (reasoning-bounded-data? candidate 16384 128)
       (digest-datum (list 'reasoning-candidate-v1 candidate))))

;; reasoning-receipt-bound?
;;   : (forall (row) (-> ReasoningReceipt (Snapshot row) Datum Boolean))
;;   : (-> ReasoningReceipt ReasoningSnapshot Datum Boolean)
;;   | doc m%
;;       Check local snapshot and inert candidate content binding for a
;;       receipt. This does not validate the candidate's intended meaning,
;;       source authority, native completion or an attached proof.
;;
;;       # Examples
;;
;;       ```scheme
;;       (reasoning-receipt-bound? receipt snapshot proposal)
;;       ;; => #t only for matching current local content
;;       ```
;;     %
(def (reasoning-receipt-bound? receipt snapshot candidate)
  (and (reasoning-receipt? receipt)
       (reasoning-snapshot-valid? snapshot)
       (equal? (reasoning-receipt-snapshot-identity receipt)
               (reasoning-snapshot-identity snapshot))
       (equal? (reasoning-receipt-snapshot-generation receipt)
               (reasoning-snapshot-generation snapshot))
       (equal? (reasoning-receipt-snapshot-digest receipt)
               (reasoning-snapshot-digest snapshot))
       (let (digest (candidate-content-digest candidate))
         (and digest
              (equal? digest
                      (reasoning-receipt-candidate-digest receipt))))))

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
               (reasoning-bounded-data? declarations 131072 128)
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
;;; Index record selection once. Reverse only reached buckets, once per node,
;;; so publication retains source-first and candidate-clause tie order.
(def (candidate-edge-index records)
  (let (index (make-hash-table))
    (for-each
     (lambda (record)
       (let (origin (caaddr record))
         (hash-put! index origin (cons record (hash-ref index origin [])))))
     records)
    index))

(def (candidate-graph-walk records origin target)
  (let ((index (candidate-edge-index records))
        (visited (make-hash-table))
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
             (with ([_ _ [_ neighbor]] record)
               (let (extended (cons record path))
                 (when (and (not support) (equal? neighbor target))
                   (set! support (reverse extended)))
                 (unless (hash-get visited neighbor)
                   (hash-put! visited neighbor #t)
                   (set! reachable (cons neighbor reachable))
                   (set! next (cons (cons neighbor extended) next))))))
           (reverse (hash-ref index node [])))
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
                            (nonmembership #f) (stratified #f))
  (make-reasoning-receipt
   status
   (reasoning-snapshot-identity snapshot)
   (reasoning-snapshot-generation snapshot)
   (reasoning-snapshot-digest snapshot)
   digest (candidate-copy-pairs query) (candidate-copy-pairs rows)
   (map (lambda (diagnostic)
          (make-reasoning-diagnostic
           (reasoning-diagnostic-code diagnostic)
           (candidate-copy-pairs (reasoning-diagnostic-path diagnostic))
           (candidate-copy-pairs (reasoning-diagnostic-detail diagnostic))))
        diagnostics)
   (and evidence
        (make-reasoning-evidence
         (reasoning-evidence-kind evidence)
         (candidate-copy-pairs (reasoning-evidence-support evidence))
         (candidate-copy-pairs (reasoning-evidence-reachable evidence))))
   proof nonmembership stratified))

(defstruct captured-stage (ok? value))
(def (capture thunk)
  (with-catch
   (lambda (failure) (make-captured-stage #f failure))
   (lambda () (make-captured-stage #t (thunk)))))

(def (failure-detail failure)
  (let (message (exception->string failure))
    (if (> (string-length message) 240)
      (substring message 0 240)
      message)))

;;; Requested evidence never changes native completion. Its finite replay
;;; checks the complete answer before a founded proof is offered.
(def (produce-receipt-stratified snapshot spec digest rows work-budget)
  (let (finite
        (candidate-finite-evidence
         snapshot spec digest 'complete rows work-budget))
    (if (eq? (finite-evidence-status finite) 'complete)
      (let-values (((status proof)
                    (candidate-produce-stratified-proof
                     snapshot spec digest 'complete rows finite
                     work-budget work-budget)))
        (make-reasoning-stratified-evidence
         status finite proof work-budget))
      (make-reasoning-stratified-evidence
       (finite-evidence-status finite) finite [] work-budget))))

;; reasoning-verify-finite-receipt
;;   : (-> ReasoningReceipt ReasoningSnapshot InertCandidate Nat Verdict)
;;   | doc m%
;;       Reinspect and replay the optional finite certificate against the
;;       current source, candidate and native answer. This also checks an
;;       empty answer without claiming a derivation for absent rows.
;;     %
(def (reasoning-verify-finite-receipt receipt snapshot candidate
                                      work-budget)
  (unless (and (exact-integer? work-budget) (> work-budget 0))
    (error "finite receipt verification needs positive work budget"
           work-budget))
  (if (and (reasoning-receipt-bound? receipt snapshot candidate)
           (eq? (reasoning-receipt-status receipt) 'complete)
           (reasoning-stratified-evidence?
            (reasoning-receipt-stratified receipt)))
    (let (checked
          (capture
           (lambda ()
             (candidate-verify-finite-evidence
              snapshot (candidate-inspect snapshot candidate)
              (reasoning-receipt-candidate-digest receipt)
              'complete (reasoning-receipt-rows receipt)
              (reasoning-stratified-evidence-finite
               (reasoning-receipt-stratified receipt))
              work-budget))))
      (if (captured-stage-ok? checked) (captured-stage-value checked) 'invalid))
    'invalid))

;; reasoning-verify-stratified-receipt
;;   : (-> ReasoningReceipt ReasoningSnapshot InertCandidate Nat Verdict)
;;   | doc m%
;;       Reinspect the candidate and independently check a completed
;;       receipt's optional founded proof against its bound finite snapshot.
;;       An absent or unsupported proof never validates by implication.
;;     %
(def (reasoning-verify-stratified-receipt receipt snapshot candidate
                                          work-budget)
  (unless (and (exact-integer? work-budget) (> work-budget 0))
    (error "stratified receipt verification needs positive work budget"
           work-budget))
  (if (and (reasoning-receipt-bound? receipt snapshot candidate)
           (eq? (reasoning-receipt-status receipt) 'complete)
           (reasoning-stratified-evidence?
            (reasoning-receipt-stratified receipt)))
    (let (evidence (reasoning-receipt-stratified receipt))
      (case (reasoning-stratified-evidence-status evidence)
        ((complete)
         (let (checked
               (capture
                (lambda ()
                  (candidate-verify-stratified-proof
                   snapshot (candidate-inspect snapshot candidate)
                   (reasoning-receipt-candidate-digest receipt)
                   'complete (reasoning-receipt-rows receipt)
                   (reasoning-stratified-evidence-finite evidence)
                   work-budget
                   (reasoning-stratified-evidence-proof evidence)
                   work-budget))))
           (if (captured-stage-ok? checked) (captured-stage-value checked) 'invalid)))
        ((bounded) 'bounded)
        ((unsupported) 'unsupported)
        (else 'invalid)))
    'invalid))

;; reasoning-attempt
;;   : (-> ReasoningSnapshot InertCandidate [Nat] [Nat] ReasoningReceipt)
;;   | doc m%
;;       Inspect a bounded candidate as data, run it against one
;;       copied source snapshot, and return a complete/rejected/unknown
;;       observation. The receipt cannot promote candidate facts to source.
;;       The optional third argument caps positive-proof body-row probes;
;;       native query completion, Why proof and ground Why-Not certificate
;;       statuses remain independent. Passing #f omits both optional positive
;;       certificates for execution-only consumers; native admission, solve,
;;       query and snapshot binding still run. An optional fourth positive work
;;       budget requests finite stratified replay and a founded proof;
;;       it never changes the native answer or completion status.
;;
;;       # Examples
;;
;;       ```scheme
;;       (reasoning-attempt snapshot
;;         '(candidate (relation path 2)
;;                     (rule (path ?x ?y) (edge ?x ?y))
;;                     (query path 1 2) (limits 8 8 16)))
;;       ;; => a receipt with status complete or a located rejection
;;       (reasoning-attempt snapshot candidate 100000 20000)
;;       ;; => also request finite stratified evidence with a 20000-step cap
;;       ```
;;     %
;;; Boundary: Structural diagnostics use candidate clause indexes, not
;;; Scheme syntax locations; planner failures retain their own messages.
(defstruct attempt-observation (rows evidence))

;;; Each stage owns its failure classification. Proof failures are diagnostics
;;; on a complete native answer; inspection/planning/solve failures are not.
(def (attempt-failure snapshot digest status query code path failure)
  (reasoning-receipt-for
   snapshot digest status query []
   (list (make-reasoning-diagnostic code path (failure-detail failure))) #f))

(def (attempt-proof-diagnostics result code)
  (if (or (not result) (captured-stage-ok? result)) []
    (list (make-reasoning-diagnostic
           code '(explain) (failure-detail (captured-stage-value result))))))

(def (attempt-proof-value result)
  (and result (captured-stage-ok? result) (captured-stage-value result)))

(def (attempt-publish snapshot spec digest query observation proof-steps stratified-steps)
  (with ((attempt-observation rows evidence) observation)
    (let* ((proof (capture (lambda ()
                   (and proof-steps
                        (candidate-positive-proof snapshot spec digest 'complete rows proof-steps)))))
           (absence (capture (lambda ()
                     (and proof-steps
                          (candidate-positive-nonmembership snapshot spec digest 'complete rows proof-steps)))))
           (stratified (and stratified-steps
                         (capture (lambda ()
                           (produce-receipt-stratified snapshot spec digest rows stratified-steps))))))
      (reasoning-receipt-for
       snapshot digest 'complete query rows
       (append (attempt-proof-diagnostics proof 'proof-failed)
               (attempt-proof-diagnostics absence 'nonmembership-failed)
               (attempt-proof-diagnostics stratified 'stratified-evidence-failed))
       evidence (attempt-proof-value proof) (attempt-proof-value absence)
       (attempt-proof-value stratified)))))

(def (attempt-observe snapshot spec digest query solved proof-steps stratified-steps)
  (let (observed
        (capture (lambda ()
          (let* ((all (relational-query-name solved (car query)))
                 (rows (filter (cut query-row-matches? (cdr query) <>) all)))
            (make-attempt-observation rows (candidate-evidence snapshot spec query rows))))))
    (cond
     ((not (captured-stage-ok? observed))
      (attempt-failure snapshot digest 'unknown query 'query-failed '(query)
                       (captured-stage-value observed)))
     ((attempt-observation-evidence (captured-stage-value observed))
      (attempt-publish snapshot spec digest query (captured-stage-value observed)
                       proof-steps stratified-steps))
     (else
      (reasoning-receipt-for
       snapshot digest 'unknown query []
       (list (make-reasoning-diagnostic 'evidence-mismatch '(explain) query)) #f)))))

(def (attempt-solve snapshot spec digest query report proof-steps stratified-steps)
  (let (diagnostic (relational-admission-report-diagnostic report))
    (if diagnostic
      (reasoning-receipt-for
       snapshot digest 'rejected query []
       (list (make-reasoning-diagnostic
              (relational-diagnostic-code diagnostic)
              (candidate-planner-path spec (relational-diagnostic-path diagnostic))
              (relational-diagnostic-detail diagnostic))) #f)
      (let (solved (capture (lambda ()
                    (relational-solve (relational-admission-report-admission report)))))
        (if (captured-stage-ok? solved)
          (attempt-observe snapshot spec digest query (captured-stage-value solved)
                           proof-steps stratified-steps)
          (attempt-failure snapshot digest 'unknown query 'solve-failed '(solve)
                           (captured-stage-value solved)))))))

(def (attempt-prepare snapshot spec digest proof-steps stratified-steps)
  (let* ((query (vector-ref (reasoning-candidate-query spec) 0))
         (prepared (capture (lambda ()
                     (relational-admit/report (candidate-program snapshot spec))))))
    (if (captured-stage-ok? prepared)
      (attempt-solve snapshot spec digest query (captured-stage-value prepared)
                     proof-steps stratified-steps)
      (attempt-failure snapshot digest 'rejected query 'planner-rejected '(program)
                       (captured-stage-value prepared)))))

(def (reasoning-attempt snapshot candidate (proof-steps 100000)
                        (stratified-steps #f))
  (unless (reasoning-snapshot-valid? snapshot)
    (error "reasoning attempt requires a current valid source snapshot" snapshot))
  (unless (or (not proof-steps)
              (and (exact-integer? proof-steps) (> proof-steps 0)))
    (error "reasoning attempt requires positive proof work budget or #f" proof-steps))
  (unless (or (not stratified-steps)
              (and (exact-integer? stratified-steps) (> stratified-steps 0)))
    (error "reasoning attempt requires positive stratified work budget" stratified-steps))
  (let* ((digest (candidate-content-digest candidate))
         (inspection (capture (cut candidate-inspect snapshot candidate))))
    (cond
     ((captured-stage-ok? inspection)
      (attempt-prepare snapshot (captured-stage-value inspection) digest
                       proof-steps stratified-steps))
     ((candidate-rejection? (captured-stage-value inspection))
      (reasoning-receipt-for
       snapshot digest 'rejected #f []
       (list (candidate-rejection-diagnostic (captured-stage-value inspection))) #f))
     (else
      (attempt-failure snapshot digest 'unknown #f 'inspector-failed '(candidate)
                       (captured-stage-value inspection))))))
