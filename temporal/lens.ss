;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: finite bounded-time projection, followed by the existing admitted engine.
;;; Invariant: open cuts have no complete evidence or definitive absence.
;;; Source-owned identities and closure declarations confer no authority.
(import (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :clan/poo/object .o .ref)
        :gerbil-ascent/temporal/value
        :gerbil-ascent/temporal/projection
        (only-in :gerbil-ascent/candidate/finite-evidence finite-evidence-closure)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt
                 reasoning-receipt-status reasoning-receipt-rows
                 reasoning-receipt-stratified reasoning-stratified-evidence-finite
                 reasoning-verify-finite-receipt
                 reasoning-verify-stratified-receipt))

(export temporal-interval temporal-window-verdict temporal-lens temporal-source temporal-solve temporal-fork temporal-scope
        temporal-lens? temporal-source? temporal-answer?
        temporal-projection temporal-status temporal-rows temporal-frontier
        temporal-receipt temporal-evidence-verdicts temporal-verify temporal-compare)

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
(def reach-output-limit (cadddr (assq 'limits (cdr reach-candidate))))

;;; One invocation owns detached coordinates, cut admission and its binding.
;;; Verification rebuilds this boundary; it never borrows an answer's snapshot.
(defstruct temporal-binding (lens source root scope cut snapshot) final: #t)
;; : (forall (scope) (-> TemporalLens TemporalSource Symbol scope TemporalBinding))
(def (prepare-binding lens source root scope)
  (unless (and (temporal-lens? lens) (temporal-source? source) (id? root))
    (error "invalid temporal solve input"))
  (let* ((l (temporal-projection lens)) (s (temporal-projection source))
         (cut (project-temporal-cut l s root))
         (snapshot (reasoning-source-snapshot
                    (snapshot-identity l s root scope) (car l)
                    (list (list 'parent 2 (temporal-cut-projection-edges cut))
                          (list 'root 1 (list (list root)))))))
    (make-temporal-binding l s root scope cut snapshot)))

;; : (-> (Maybe ReasoningReceipt) ReasoningSnapshot Boolean)
(def (complete-receipt? receipt snapshot)
  (and receipt (eq? (reasoning-receipt-status receipt) 'complete)
       (eq? (reasoning-verify-finite-receipt receipt snapshot reach-candidate 100000) 'valid)
       ;; Native output limits include source rows as well as derived rows.
       ;; Read the supplied closure only after independent replay admitted it.
       (<= (apply + (map (lambda (entry) (length (caddr entry)))
                        (finite-evidence-closure
                         (reasoning-stratified-evidence-finite
                          (reasoning-receipt-stratified receipt))))) reach-output-limit)
       (or (null? (reasoning-receipt-rows receipt))
           (eq? (reasoning-verify-stratified-receipt receipt snapshot reach-candidate 100000) 'valid))))

;; : (-> TemporalBinding Symbol [Row] AnswerData)
(def (answer-projection binding status rows)
  (using (binding :- temporal-binding)
    (let (rejection (temporal-cut-projection-rejection binding.cut))
      (list status binding.lens binding.source binding.root rows
            (if rejection (list (list rejection))
              (temporal-cut-projection-frontier binding.cut)) binding.scope))))

;; : (-> ReasoningReceipt Symbol [Row])
(def (receipt-root-rows receipt root)
  (list-sort row<? (filter (lambda (row) (eq? (car row) root))
                          (reasoning-receipt-rows receipt))))

;; : (forall (scope) (-> TemporalLens TemporalSource Symbol scope TemporalAnswer))
;; : (-> Lens Source Root Scope Answer)
(def (solve lens source root scope-value)
  (using (binding (prepare-binding lens source root scope-value) :- temporal-binding)
    (let* ((snapshot binding.snapshot)
           (frontier (temporal-cut-projection-frontier binding.cut))
           (rejection (temporal-cut-projection-rejection binding.cut))
           (receipt (and (not rejection) (null? frontier)
                         (reasoning-attempt snapshot reach-candidate 100000 100000)))
           (valid (complete-receipt? receipt snapshot))
           (rows (if valid (receipt-root-rows receipt root) []))
           (status (cond (rejection 'rejected)
                         ((pair? frontier) 'partial)
                         (valid 'complete) (else 'unknown)))
           (answer (value-object 'ascent.temporal-answer.v1
                     (answer-projection binding status rows))))
      ;; Evidence objects are retained separately from the copied projection.
      (let ((receipt-value receipt) (snapshot-value snapshot))
        (.o (:: @ answer) receipt: receipt-value snapshot: snapshot-value)))))

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
  (using (binding (prepare-binding lens source root (temporal-scope answer)) :- temporal-binding)
    (let (receipt (and (eq? (temporal-status answer) 'complete)
                      (not (temporal-cut-projection-rejection binding.cut))
                      (null? (temporal-cut-projection-frontier binding.cut))
                      (temporal-receipt answer)))
      (if (and (complete-receipt? receipt binding.snapshot)
               (equal? (answer-projection binding 'complete (receipt-root-rows receipt root))
                       (temporal-projection answer)))
        'valid 'invalid))))

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
