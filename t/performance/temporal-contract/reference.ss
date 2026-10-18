;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: finite bounded-time projection, followed by the existing admitted engine.
;;; Invariant: open cuts have no complete evidence or definitive absence.
;;; Source-owned identities and closure declarations confer no authority.
(import (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :clan/poo/object .o .ref .slot? object?)
        (only-in :gerbil-ascent/temporal/graph temporal-cut-cyclic?)
        (only-in :gerbil-ascent/candidate/types reasoning-bounded-data?)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt
                 reasoning-receipt-status reasoning-receipt-rows
                 reasoning-verify-finite-receipt
                 reasoning-verify-stratified-receipt))

(export temporal-interval temporal-window-verdict temporal-lens temporal-source temporal-solve temporal-fork temporal-scope
        temporal-lens? temporal-source? temporal-answer?
        temporal-projection temporal-status temporal-rows temporal-frontier
        temporal-receipt temporal-evidence-verdicts temporal-verify temporal-compare)

;; : (forall (a) (-> a a))
;; : (-> InertDatum InertDatum)
(def (copy-data value)
  (if (pair? value)
    (cons (copy-data (car value)) (copy-data (cdr value))) value))
;; : (-> Symbol Symbol Boolean)
;; : (-> EventId EventId Boolean)
(def (id<? a b) (string<? (symbol->string a) (symbol->string b)))
;; : (-> (List Symbol) (List Symbol) Boolean)
;; : (-> ParentEdge ParentEdge Boolean)
(def (row<? a b)
  (if (eq? (car a) (car b)) (id<? (cadr a) (cadr b))
    (id<? (car a) (car b))))
;; : (forall (a) (-> a Boolean))
;; : (-> SchemeValue Boolean)
(def (position? x) (and (exact-integer? x) (<= 0 x)))
;; : (forall (a) (-> a Boolean))
;; : (-> SchemeValue Boolean)
(def (id? x) (and (symbol? x) (not (eq? x 'unknown))))
;; : (forall (a) (-> (List a) Boolean))
;; : (-> InertList Boolean)
(def (unique? xs)
  (or (null? xs) (and (not (member (car xs) (cdr xs))) (unique? (cdr xs)))))
;; : (forall (a) (-> a Nat Boolean))
;; : (-> SchemeValue ElementCap Boolean)
(def (bounded-list? x cap)
  (and (reasoning-bounded-data? x 16384 32) (list? x) (<= (length x) cap)))

;;; A POO object's projection returns a fresh tree. Constructors capture only
;;; checked inert data: no clock, Provider or rule-time callback is admitted.
;; : (forall (a) (-> Symbol a (TemporalValue a)))
;; : (-> ValueKind InertDatum TemporalValue)
(def (value-object kind-value data)
  (let (owned (copy-data data))
    (.o kind: kind-value projection: (lambda () (copy-data owned)))))
;; : (forall (a) (-> a Symbol Boolean))
;; : (-> SchemeValue ValueKind Boolean)
(def (kind? x kind)
  (and (object? x) (.slot? x 'kind) (eq? (.ref x 'kind) kind)
       (.slot? x 'projection) (procedure? (.ref x 'projection))))
;; : (-> TemporalValue Boolean)
;; : (-> TemporalValue LensShape)
(def (temporal-lens? x) (kind? x 'ascent.temporal-lens.v1))
;; : (-> TemporalValue Boolean)
;; : (-> TemporalValue SourceShape)
(def (temporal-source? x) (kind? x 'ascent.temporal-source.v1))
;; : (-> TemporalValue Boolean)
;; : (-> TemporalValue AnswerShape)
(def (temporal-answer? x) (kind? x 'ascent.temporal-answer.v1))
;; : (forall (a) (-> (TemporalValue a) a))
;; : (-> TemporalValue DetachedDatum)
(def (temporal-projection x)
  (unless (or (temporal-lens? x) (temporal-source? x) (temporal-answer? x)
              (kind? x 'ascent.temporal-interval.v1))
    (error "expected ASCENT temporal value"))
  ((.ref x 'projection)))

;;; Closed bounds describe uncertainty about one valid-time point, not event
;;; duration. unknown lower means 0; unknown upper means no finite bound.
;; : (-> Endpoint Endpoint TemporalInterval)
;; : (-> LowerBound UpperBound Interval)
(def (temporal-interval lower upper)
  (let (data (list 'between lower upper))
    (unless (valid-time? data) (error "invalid temporal interval"))
    (value-object 'ascent.temporal-interval.v1 data)))
;; : (-> SchemeValue Boolean)
;; : (-> ValidTimeDatum WellFormed)
(def (valid-time? value)
  (or (position? value) (eq? value 'unknown)
      (and (list? value) (= (length value) 3) (eq? (car value) 'between)
           (or (position? (cadr value)) (eq? (cadr value) 'unknown))
           (or (position? (caddr value)) (eq? (caddr value) 'unknown))
           (or (eq? (cadr value) 'unknown) (eq? (caddr value) 'unknown)
               (<= (cadr value) (caddr value))))))
;; : (-> SchemeValue ValidTimeDatum)
;; : (-> ValidTimeInput CheckedDatum)
(def (valid-time-data value)
  (let (data (if (kind? value 'ascent.temporal-interval.v1)
              (temporal-projection value) value))
    (unless (valid-time? data) (error "invalid valid time"))
    data))
;; : (-> ValidTimeDatum Nat)
;; : (-> CheckedDatum LowerBound)
(def (time-lower value)
  (cond ((position? value) value) ((eq? value 'unknown) 0)
        ((eq? (cadr value) 'unknown) 0) (else (cadr value))))
;; : (-> ValidTimeDatum (Maybe Nat))
;; : (-> CheckedDatum UpperBoundOrFalse)
(def (time-upper value)
  (cond ((position? value) value) ((eq? value 'unknown) #f)
        ((eq? (caddr value) 'unknown) #f) (else (caddr value))))
;; : (-> SchemeValue Nat Nat Symbol)
;; : (-> ValidTimeInput Start End ThreeValuedVerdict)
(def (temporal-window-verdict value start end)
  (unless (and (position? start) (position? end) (< start end))
    (error "invalid temporal window"))
  (let* ((data (valid-time-data value)) (lower (time-lower data))
         (upper (time-upper data)))
    (cond ((or (>= lower end) (and upper (< upper start))) 'false)
          ((and upper (<= start lower) (< upper end)) 'true)
          (else 'unknown))))

;;; Positions are exact nonnegative values in one caller-declared clock.
;;; Window is half-open. horizon counts edges from the selected root.
;; : (forall (id) (-> Nat id Nat Nat Nat id (List id) Nat Boolean TemporalLens))
;; : (-> Generation Clock Start End KnowledgeAsOf CutId Members Horizon ClosedFlag Lens)
(def (temporal-lens generation clock start end as-of cut members horizon closed?)
  (unless (and (position? generation) (id? clock) (position? start)
               (position? end) (< start end) (position? as-of) (id? cut)
               (bounded-list? members 256) (andmap id? members) (unique? members)
               (position? horizon) (<= horizon 128) (boolean? closed?))
    (error "invalid temporal lens"))
  (value-object 'ascent.temporal-lens.v1
                (list generation clock start end as-of cut (list-sort id<? members) horizon closed?)))

;;; Events: (event-id valid-time knowledge-position). Interval POO values
;;; are captured as canonical inert bounds and included in native binding.
;;; Parents: (parent-id child-id), a distinct source-owned order relation.
;; : (forall (id) (-> id Nat id (List Datum) (List (Pair id id)) TemporalSource))
;; : (-> SourceId Generation Clock Events ParentEdges Source)
(def (temporal-source identity generation clock events parents)
  (unless (and (id? identity) (position? generation) (id? clock)
               (and (list? events) (<= (length events) 256)) (bounded-list? parents 512)
               (andmap (lambda (e)
                         (and (list? e) (= (length e) 3) (id? (car e))
                              (valid-time? (valid-time-data (cadr e)))
                              (position? (caddr e)))) events)
               (unique? (map car events))
               (andmap (lambda (e)
                         (and (list? e) (= (length e) 2)
                              (andmap id? e))) parents)
               (unique? parents))
    (error "invalid temporal source"))
  (value-object 'ascent.temporal-source.v1
                (list identity generation clock
                      (list-sort (lambda (a b) (id<? (car a) (car b)))
                                 (map (lambda (e) (list (car e) (valid-time-data (cadr e)) (caddr e))) events))
                      (list-sort row<? parents))))

;;; Binding boundary: native evidence includes the full temporal coordinates,
;;; even when a changed window/cut/scope yields the same projected graph.
;;; This is local content integrity, never source authentication.
;; : (forall (scope) (-> Datum Datum Symbol scope String))
;; : (-> LensData SourceData Root Scope SnapshotIdentity)
(def (snapshot-identity lens source root scope)
  (hex-encode (sha256 (string->utf8
                       (call-with-output-string ""
                         (lambda (port)
                           (write (list 'ascent.temporal-binding.v1 lens source root scope) port)))))))

;;; Fixed positive program. Temporal projection cannot introduce negation
;;; over an open frontier. The candidate boundary produces existing evidence.
(def reach-candidate
  '(candidate (relation reach 2)
     (rule (reach ?x ?y) (root ?x) (parent ?x ?y))
     (rule (reach ?x ?z) (reach ?x ?y) (parent ?y ?z))
     (query reach ?x ?y) (limits 1024 4096 4096)))

;;; Facts belong to one detached projection. Canonical lists still own
;;; iteration order; these records never escape into a value or receipt.
;; Fixed layout stays private; field macros keep positions out of consumers.
(defrule (make-projection-node data member eligible outgoing discovery)
  (vector data member eligible outgoing discovery #f))
;;; First source occurrence owns diagnostics even for duplicate supplied IDs.
(defrule (projection-node-data node) (vector-ref node 0))
;;; Cut membership remains independent of window eligibility and event availability.
(defrule (projection-node-member? node) (vector-ref node 1))
;;; Missing events still retain their admitted cut membership.
(defrule (projection-node-member?-set! node value) (vector-set! node 1 value))
;;; Definitive window membership is separate from completeness of the cut.
(defrule (projection-node-eligible? node) (vector-ref node 2))
;;; Eligibility is filled after validation and cannot close an open frontier.
(defrule (projection-node-eligible?-set! node value) (vector-set! node 2 value))
;;; Stable original ordinals preserve the source-first edge witnesses.
(defrule (projection-node-outgoing node) (vector-ref node 3))
;;; Only invocation-owned adjacency changes while source parent rows stay intact.
(defrule (projection-node-outgoing-set! node value) (vector-set! node 3 value))
;;; Settled vertices and current-layer witnesses occupy distinct states.
(defrule (projection-node-discovery node) (vector-ref node 4))
;;; A layer settles only when the horizon check permits another step.
(defrule (projection-node-discovery-set! node value) (vector-set! node 4 value))
;;; Only validated inert coordinates admit reuse of a window verdict.
(defrule (projection-node-window node) (vector-ref node 5))
;;; Callback-backed projections cannot populate this invocation memo.
(defrule (projection-node-window-set! node value) (vector-set! node 5 value))
(def (projection-index events members)
  (let (table (make-hash-table-eq size: (length events)))
    (for-each (lambda (event)
      ;; Preserve assq's first occurrence for supplied projections as well.
      (unless (hash-get table (car event))
        (hash-put! table (car event) (make-projection-node event #f #f [] #f)))) events)
    (for-each (lambda (id)
      (let (entry (hash-get table id))
        (if entry (projection-node-member?-set! entry #t)
            (hash-put! table id (make-projection-node #f #t #f [] #f))))) members)
    table))
(def (cut-member? index id)
  (let (entry (hash-get index id)) (and entry (projection-node-member? entry))))
(def (indexed-event index id)
  (let (entry (hash-get index id)) (and entry (projection-node-data entry))))
(def (eligible-member? index id)
  (let (entry (hash-get index id)) (and entry (projection-node-eligible? entry))))
(def (checked-window-verdict data start end)
  ;; Canonical exact points admit a direct comparison. Other admitted bounds
  ;; retain the same three-valued interval formula as the public wrapper.
  (if (exact-integer? data)
    (if (and (<= start data) (< data end)) 'true 'false)
    (let ((lower (time-lower data)) (upper (time-upper data)))
      (cond ((or (>= lower end) (and upper (< upper start))) 'false)
            ((and upper (<= start lower) (< upper end)) 'true)
            (else 'unknown)))))
(def (select-eligible! index events as-of start end)
  (for-each (lambda (event)
    (let (node (hash-ref index (car event)))
      (when (and (projection-node-member? node) (<= (caddr event) as-of)
                 (eq? (or (and (eq? event (projection-node-data node))
                               (projection-node-window node))
                          (temporal-window-verdict (cadr event) start end)) 'true))
        (projection-node-eligible?-set! node #t)))) events))

;; Index stable edge ordinals once. Layer discovery may visit parents in any
;; order; minimum incoming ordinal recovers the original first-edge witness.
;; Discovery entries are #t for settled vertices or an edge for this layer.
(def (indexed-horizon-frontier edges root horizon index)
  (let rank-edges ((rest edges) (rank 0))
    (unless (null? rest)
      (let* ((edge (car rest)) (from (hash-ref index (car edge))))
        (projection-node-outgoing-set! from (cons (cons rank (cadr edge)) (projection-node-outgoing from)))
        (rank-edges (cdr rest) (+ rank 1)))))
  ;; Restore original edge order inside each source bucket. A single-parent
  ;; layer can then emit reverse first-discovery order directly.
  (hash-for-each (lambda (_ node)
    (projection-node-outgoing-set! node (reverse (projection-node-outgoing node)))) index)
  (let (root-node (hash-get index root))
    (and root-node
      (begin
        (projection-node-discovery-set! root-node #t)
        (let loop ((front (list root)) (depth 0))
          (let (ids [])
            (for-each (lambda (from)
              (for-each (lambda (edge)
                (let* ((target (cdr edge)) (node (hash-ref index target))
                       (first (projection-node-discovery node)))
                  (cond ((not first)
                         (projection-node-discovery-set! node edge)
                         (set! ids (cons target ids)))
                        ((and (pair? first) (< (car edge) (car first)))
                         (projection-node-discovery-set! node edge)))))
                (projection-node-outgoing (hash-ref index from)))) front)
            (let (next (if (or (null? ids) (null? (cdr ids)) (null? (cdr front))) ids
                        (map cdr (list-sort (lambda (a b) (> (car a) (car b)))
                          (map (lambda (id) (projection-node-discovery (hash-ref index id))) ids)))))
              (cond ((null? next) #f)
                    ((>= depth horizon) next)
                    (else (for-each (lambda (id)
                            (projection-node-discovery-set! (hash-ref index id) #t)) next)
                          (loop next (+ depth 1)))))))))))

;; Zero horizon admits one source-ordered edge pass without building adjacency.
(def (horizon-frontier edges root horizon index)
  (if (zero? horizon)
    (let ((root-node (hash-get index root)) (next []))
      (when root-node (projection-node-discovery-set! root-node #t))
      (for-each (lambda (edge)
        (when (eq? (car edge) root)
          (let (node (hash-ref index (cadr edge)))
            (unless (projection-node-discovery node)
              (projection-node-discovery-set! node #t)
              (set! next (cons (cadr edge) next)))))) edges)
      (and (pair? next) next))
    (indexed-horizon-frontier edges root horizon index)))

;; : (forall (scope) (-> TemporalLens TemporalSource Symbol scope TemporalAnswer))
;; : (-> Lens Source Root Scope Answer)
(def (solve lens source root scope-value)
  (unless (and (temporal-lens? lens) (temporal-source? source) (id? root))
    (error "invalid temporal solve input"))
  (let* ((l (temporal-projection lens)) (s (temporal-projection source))
         (generation (list-ref l 0)) (clock (list-ref l 1))
         (start (list-ref l 2)) (end (list-ref l 3)) (as-of (list-ref l 4))
         (members (list-ref l 6)) (horizon (list-ref l 7))
         (events (list-ref s 3)) (parents (list-ref s 4))
         (index (projection-index events members))
         (canonical-window? (and (position? start) (position? end) (< start end)
                                 (andmap (lambda (event) (valid-time? (cadr event))) events)))
         (cut-edges (filter (lambda (edge) (cut-member? index (cadr edge))) parents))
         (frontier []) (rejection #f))
    (def (open! code detail) (set! frontier (cons (list code detail) frontier)))
    (def (reject! code) (unless rejection (set! rejection code)))
    (unless (= generation (list-ref s 1)) (reject! 'generation-mismatch))
    (unless (eq? clock (list-ref s 2)) (reject! 'clock-mismatch))
    (unless (list-ref l 8) (open! 'open-cut (list-ref l 5)))
    (unless (cut-member? index root) (reject! 'root-outside-cut))
    (for-each
     (lambda (id)
       (let* ((node (hash-ref index id)) (event (projection-node-data node)))
         (cond ((not event) (open! 'missing-event id))
               ((> (caddr event) as-of) (open! 'knowledge-unavailable id))
               (else
                (let (verdict (if canonical-window?
                               (checked-window-verdict (cadr event) start end)
                               (temporal-window-verdict (cadr event) start end)))
                  ;; Only inert canonical bounds are stable across calls.
                  ;; Callback-backed supplied values keep their original calls.
                  (when canonical-window? (projection-node-window-set! node verdict))
                  (when (eq? verdict 'unknown) (open! 'unknown-valid-time id)))))))
     members)
    (for-each
     (lambda (edge)
       (unless (cut-member? index (car edge)) (open! 'missing-parent edge))
       (let ((from (indexed-event index (car edge))) (to (indexed-event index (cadr edge))))
         (when (and from to)
           (let ((lower-from (time-lower (cadr from)))
                 (upper-from (time-upper (cadr from)))
                 (lower-to (time-lower (cadr to)))
                 (upper-to (time-upper (cadr to))))
             (cond ((and upper-to (> lower-from upper-to))
                    (reject! 'order-violation))
                   ((not (and upper-from (<= upper-from lower-to)))
                    (open! 'unknown-parent-order edge))))))) cut-edges)
    ;; Parent closure and cycles are checked even outside the valid window.
    (when (temporal-cut-cyclic? cut-edges) (reject! 'cyclic-cut))
    (select-eligible! index events as-of start end)
    (let* ((edges (filter (lambda (edge)
                    (and (eligible-member? index (car edge))
                         (eligible-member? index (cadr edge)))) cut-edges))
           (boundary (horizon-frontier edges root horizon index)))
      ;; An open frontier is explicit; no absence claim or complete receipt.
      (when boundary (open! 'horizon-frontier boundary))
      (let* ((snapshot (reasoning-source-snapshot
                        (snapshot-identity l s root scope-value) generation (list (list 'parent 2 edges) (list 'root 1 (list (list root))))))
             (receipt (and (not rejection) (null? frontier)
                           (reasoning-attempt snapshot reach-candidate 100000 100000)))
             (valid (and receipt (eq? (reasoning-receipt-status receipt) 'complete)
                         (eq? (reasoning-verify-finite-receipt
                               receipt snapshot reach-candidate 100000) 'valid)
                         (or (null? (reasoning-receipt-rows receipt))
                             (eq? (reasoning-verify-stratified-receipt
                                   receipt snapshot reach-candidate 100000) 'valid))))
             (rows (if valid
                     (list-sort row<?
                                (filter (lambda (row) (eq? (car row) root))
                                        (reasoning-receipt-rows receipt))) []))
             (status (cond (rejection 'rejected)
                           ((pair? frontier) 'partial)
                           (valid 'complete) (else 'unknown))))
        ;; Evidence objects are retained separately from the copied projection.
        (let (answer (value-object 'ascent.temporal-answer.v1
                       (list status l s root rows
                             (if rejection (list (list rejection))
                               (reverse frontier)) scope-value)))
          (let ((receipt-value receipt) (snapshot-value snapshot))
            (.o (:: @ answer) receipt: receipt-value snapshot: snapshot-value)))))))

;; : (-> TemporalLens TemporalSource Symbol TemporalAnswer)
;; : (-> Lens Source Root Answer)
(def (temporal-solve lens source root)
  (solve lens source root '(supplied-snapshot)))

;;; A fork requires separate source/cut names, remains labelled hypothetical,
;;; and retains the base coordinates. It cannot modify an accepted answer.
;; : (-> TemporalAnswer TemporalLens TemporalSource TemporalAnswer)
;; : (-> CompleteBase HypotheticalLens HypotheticalSource HypotheticalAnswer)
(def (temporal-fork answer hypothetical-lens hypothetical-source)
  (unless (and (temporal-answer? answer)
               (eq? (temporal-status answer) 'complete)
               (verified-answer? answer)
               (temporal-lens? hypothetical-lens)
               (temporal-source? hypothetical-source))
    (error "temporal fork requires a complete base and explicit hypothetical inputs"))
  (let* ((base (temporal-projection answer))
         (bl (cadr base)) (bs (caddr base))
         (l (temporal-projection hypothetical-lens))
         (s (temporal-projection hypothetical-source)))
    (unless (and (= (car l) (car bl))
                 (not (eq? (list-ref l 5) (list-ref bl 5)))
                 (not (eq? (car s) (car bs)))
                 (equal? (list (cadr l) (list-ref l 2) (list-ref l 3)
                               (list-ref l 4) (list-ref l 7))
                         (list (cadr bl) (list-ref bl 2) (list-ref bl 3)
                               (list-ref bl 4) (list-ref bl 7))))
      (error "hypothetical source/cut must be separately named under the same lens policy"))
    (solve hypothetical-lens hypothetical-source (list-ref base 3)
           (list 'hypothetical (car bs) (car bl) (list-ref bl 5)))))

;; : (-> TemporalValue Scope)
;; : (-> TemporalValue AnswerScope)
(def (temporal-scope answer) (list-ref (temporal-projection answer) 6))
;; : (-> TemporalValue Symbol)
;; : (-> TemporalValue CompletionStatus)
(def (temporal-status answer) (list-ref (temporal-projection answer) 0))
;; : (-> TemporalValue (List Datum))
;; : (-> TemporalValue DetachedQueryRows)
(def (temporal-rows answer) (list-ref (temporal-projection answer) 4))
;; : (-> TemporalValue (List Datum))
;; : (-> TemporalValue DetachedFrontier)
(def (temporal-frontier answer) (list-ref (temporal-projection answer) 5))
;; : (-> TemporalAnswer (Maybe ReasoningReceipt))
;; : (-> Answer NativeReceiptOrFalse)
(def (temporal-receipt answer)
  (unless (temporal-answer? answer) (error "expected temporal answer"))
  (.ref answer 'receipt))

;;; Empty queries have finite closure evidence, but no founded Why-Not proof.
;; : (-> TemporalAnswer (List Symbol))
;; : (-> Answer FiniteAndFoundedVerdicts)
(def (temporal-evidence-verdicts answer)
  (let (receipt (temporal-receipt answer))
    (if receipt
      (list (reasoning-verify-finite-receipt
             receipt (.ref answer 'snapshot) reach-candidate 100000)
            (reasoning-verify-stratified-receipt
             receipt (.ref answer 'snapshot) reach-candidate 100000))
      '(not-produced not-produced))))

;;; Bind all lens/source/root coordinates, including equal-answer generations.
;; : (-> TemporalLens TemporalSource Symbol TemporalAnswer Symbol)
;; : (-> Lens Source Root Answer Verdict)
(def (temporal-verify lens source root answer)
  (unless (and (temporal-lens? lens) (temporal-source? source)
               (temporal-answer? answer)) (error "invalid temporal verification input"))
  (let (fresh (solve lens source root (temporal-scope answer)))
    (if (and (eq? (temporal-status answer) 'complete)
             (eq? (temporal-status fresh) 'complete)
             (equal? (temporal-projection fresh) (temporal-projection answer))
             (let ((receipt (temporal-receipt answer))
                   (snapshot (.ref fresh 'snapshot)))
               (and receipt
                    (eq? (reasoning-verify-finite-receipt
                          receipt snapshot reach-candidate 100000) 'valid)
                    (or (null? (temporal-rows answer))
                        (eq? (reasoning-verify-stratified-receipt
                              receipt snapshot reach-candidate 100000) 'valid)))))
      'valid 'invalid)))

;;; Evidence boundary: composed operations recheck actual receipts before
;;; consuming complete projections, including objects extended by the caller.
;; : (-> TemporalAnswer Boolean)
;; : (-> Answer LocallyVerified)
(def (verified-answer? answer)
  (let (data (temporal-projection answer))
    (eq? (temporal-verify (apply temporal-lens (cadr data))
                          (apply temporal-source (caddr data))
                          (list-ref data 3) answer) 'valid)))

;;; A tuple delta is not a domain causal effect. Cut membership may change
;;; across generations, but clock/window/as-of/horizon/closure policy may not.
;; : (-> TemporalAnswer TemporalAnswer (List (List Datum)))
;; : (-> CompleteBefore CompleteAfter TupleDelta)
(def (temporal-compare before after)
  (let* ((b (temporal-projection before)) (a (temporal-projection after))
         (bl (cadr b)) (al (cadr a)))
    (unless (and (eq? (car b) 'complete) (eq? (car a) 'complete)
                 (verified-answer? before) (verified-answer? after)
                 (< (car bl) (car al))
                 (eq? (car (list-ref b 2)) (car (list-ref a 2)))
                 (equal? (temporal-scope before) (temporal-scope after))
                 (equal? (list (cadr bl) (list-ref bl 2) (list-ref bl 3)
                               (list-ref bl 4) (list-ref bl 7) (list-ref bl 8)
                               (list-ref b 3))
                         (list (cadr al) (list-ref al 2) (list-ref al 3)
                               (list-ref al 4) (list-ref al 7) (list-ref al 8)
                               (list-ref a 3))))
      (error "temporal comparison requires complete compatible answers"))
    (list (filter (lambda (x) (not (member x (list-ref b 4)))) (list-ref a 4))
          (filter (lambda (x) (not (member x (list-ref a 4)))) (list-ref b 4)))))
