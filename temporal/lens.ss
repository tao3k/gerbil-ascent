;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: finite point-time projection, followed by the existing admitted engine.
;;; Invariant: open cuts have no complete evidence or definitive absence.
;;; Source-owned identities and closure declarations confer no authority.
(import (only-in :clan/poo/object .o .ref .slot? object?)
        (only-in :gerbil-ascent/candidate/types reasoning-bounded-data?)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt
                 reasoning-receipt-status reasoning-receipt-rows
                 reasoning-verify-finite-receipt
                 reasoning-verify-stratified-receipt))

(export temporal-lens temporal-source temporal-solve temporal-fork temporal-scope
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
  (unless (or (temporal-lens? x) (temporal-source? x) (temporal-answer? x))
    (error "expected ASCENT temporal value"))
  ((.ref x 'projection)))

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

;;; Events: (event-id valid-position-or-unknown knowledge-position).
;;; Parents: (parent-id child-id), a distinct source-owned order relation.
;; : (forall (id) (-> id Nat id (List Datum) (List (Pair id id)) TemporalSource))
;; : (-> SourceId Generation Clock Events ParentEdges Source)
(def (temporal-source identity generation clock events parents)
  (unless (and (id? identity) (position? generation) (id? clock)
               (bounded-list? events 256) (bounded-list? parents 512)
               (andmap (lambda (e)
                         (and (list? e) (= (length e) 3) (id? (car e))
                              (or (position? (cadr e)) (eq? (cadr e) 'unknown))
                              (position? (caddr e)))) events)
               (unique? (map car events))
               (andmap (lambda (e)
                         (and (list? e) (= (length e) 2)
                              (andmap id? e))) parents)
               (unique? parents))
    (error "invalid temporal source"))
  (value-object 'ascent.temporal-source.v1
                (list identity generation clock
                      (list-sort (lambda (a b) (id<? (car a) (car b))) events)
                      (list-sort row<? parents))))

;;; Fixed positive program. Temporal projection cannot introduce negation
;;; over an open frontier. The candidate boundary produces existing evidence.
(def reach-candidate
  '(candidate (relation reach 2)
     (rule (reach ?x ?y) (root ?x) (parent ?x ?y))
     (rule (reach ?x ?z) (reach ?x ?y) (parent ?y ?z))
     (query reach ?x ?y) (limits 1024 4096 4096)))

;; : (forall (id) (-> id (List (Pair id id)) (List id)))
;; : (-> EventId ParentEdges EventIds)
(def (reachable root edges)
  (let loop ((known (list root)) (front (list root)))
    (if (null? front) known
      (let (next (filter (lambda (x) (not (memq x known)))
                        (foldl (lambda (e xs)
                                 (if (and (memq (car e) front)
                                          (not (memq (cadr e) xs)))
                                   (cons (cadr e) xs) xs)) [] edges)))
        (loop (foldl cons known next) next)))))

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
         (cut-edges (filter (lambda (e) (memq (cadr e) members)) parents))
         (frontier []) (rejection #f))
    (def (open! code detail) (set! frontier (cons (list code detail) frontier)))
    (def (reject! code) (unless rejection (set! rejection code)))
    (unless (= generation (list-ref s 1)) (reject! 'generation-mismatch))
    (unless (eq? clock (list-ref s 2)) (reject! 'clock-mismatch))
    (unless (list-ref l 8) (open! 'open-cut (list-ref l 5)))
    (unless (memq root members) (reject! 'root-outside-cut))
    (for-each
     (lambda (id)
       (let (event (assq id events))
         (cond ((not event) (open! 'missing-event id))
               ((> (caddr event) as-of) (open! 'knowledge-unavailable id))
               ((eq? (cadr event) 'unknown) (open! 'unknown-valid-time id)))))
     members)
    (for-each
     (lambda (edge)
       (unless (memq (car edge) members) (open! 'missing-parent edge))
       (let ((from (assq (car edge) events)) (to (assq (cadr edge) events)))
         (when (and from to (position? (cadr from)) (position? (cadr to))
                    (> (cadr from) (cadr to)))
           (reject! 'order-violation)))) cut-edges)
    ;; Parent closure and cycles are checked even outside the valid window.
    (for-each (lambda (e)
                (when (memq (car e) (reachable (cadr e) cut-edges))
                  (reject! 'cyclic-cut))) cut-edges)
    (let* ((eligible (filter
                      (lambda (e)
                        (and (memq (car e) members) (<= (caddr e) as-of)
                             (position? (cadr e))
                             (<= start (cadr e)) (< (cadr e) end))) events))
           (ids (map car eligible))
           (edges (filter (lambda (e) (and (memq (car e) ids)
                                           (memq (cadr e) ids))) cut-edges))
           (within (list root)))
      ;; An open frontier is explicit; no absence claim or complete receipt.
      (let loop ((front (if (memq root ids) (list root) [])) (depth 0))
        (let (next (filter (lambda (x) (not (memq x within)))
                          (foldl (lambda (e xs)
                                   (if (and (memq (car e) front)
                                            (not (memq (cadr e) xs)))
                                     (cons (cadr e) xs) xs)) [] edges)))
          (cond ((null? next) (void))
                ((>= depth horizon) (open! 'horizon-frontier next))
                (else (set! within (foldl cons within next))
                      (loop next (+ depth 1))))))
      (let* ((snapshot (reasoning-source-snapshot
                        (list-ref s 0) generation (list (list 'parent 2 edges) (list 'root 1 (list (list root))))))
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

;;; A tuple delta is not a domain causal effect. Cut membership may change
;;; across generations, but clock/window/as-of/horizon/closure policy may not.
;; : (-> TemporalAnswer TemporalAnswer (List (List Datum)))
;; : (-> CompleteBefore CompleteAfter TupleDelta)
(def (temporal-compare before after)
  (let* ((b (temporal-projection before)) (a (temporal-projection after))
         (bl (cadr b)) (al (cadr a)))
    (unless (and (eq? (car b) 'complete) (eq? (car a) 'complete)
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
