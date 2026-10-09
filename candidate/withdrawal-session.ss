;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One serialized positive owner publishes maintained rows, source generation
;;; and grounded support together. Native evaluation qualifies the initial cut.
(import (only-in :clan/poo/object .o .ref object? .slot?)
        (only-in :clan/poo/mop define-type validate .defgeneric)
        (only-in :core/types PooFlowNativeObjectContract. poo-flow-predicate-contract)
        (only-in "datum.ss" candidate-copy-pairs reasoning-bounded-data?)
        (only-in "types.ss" reasoning-snapshot-valid? reasoning-snapshot-relations
                 reasoning-snapshot-identity reasoning-snapshot-generation
                 reasoning-candidate-query)
        (only-in "reasoning.ss" reasoning-source-snapshot candidate-content-digest)
        (only-in "program.ss" candidate-inspect candidate-program)
        (only-in "funs.ss" candidate-bind-atom)
        (only-in "provenance-graph.ss" candidate-positive-provenance
                 candidate-open-provenance-maintenance
                 candidate-provenance-preview-withdraw candidate-provenance-compact
                 provenance-maintenance-size)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session
                 gerbil-ascent-session-run))
(export candidate-open-withdrawal-session candidate-withdrawal-observe
        candidate-withdrawal-session! candidate-withdrawal-compact!
        candidate-withdrawal-support-size GerbilAscentWithdrawalSessionContract)

;;; Admit the named procedure protocol as one responsibility. Four identical
;;; per-slot evidence trees add construction cost without richer method types.
;;; Every method is still required and checked before this owner escapes.
;; : (-> Any Boolean)
(def (withdrawal-operations? candidate)
  (and (object? candidate)
       (andmap (lambda (slot) (and (.slot? candidate slot) (procedure? (.ref candidate slot))))
               '(.observe .withdraw .compact .support-size))))

(define-type (GerbilAscentWithdrawalSessionContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/grounded-withdrawal-session
  proto: (.o)
  responsibilities:
  (.o .operations: (poo-flow-predicate-contract 'ascent/withdrawal-operations
                    withdrawal-operations? (lambda (_v _c) []))))

;;; Copy source identity as well as declaration spines: strings are mutable.
;; : (-> ReasoningSnapshot Nat SourceDeclarations ReasoningSnapshot)
(def (owned-snapshot source generation declarations)
  (let (id (reasoning-snapshot-identity source))
    (reasoning-source-snapshot (if (string? id) (string-copy id) id)
                              generation declarations)))

;;; One accessor owns the private relation-to-token list representation.
;; : (-> OccurrenceMap Symbol SourceTokens)
(def (source-tokens occurrences name) (cdr (assq name occurrences)))

;;; Selectors refer to one-based occurrences in the CURRENT source cut. All
;;; selectors are checked before removal; duplicate row values remain distinct.
;; : (-> ReasoningSnapshot OccurrenceMap SourceOccurrences (Values ReasoningSnapshot OccurrenceMap SourceOccurrences))
(def (withdraw-source-cut source occurrences selectors)
  (unless (and (reasoning-bounded-data? selectors 131072 128)
               (list? selectors) (pair? selectors))
    (error "withdrawal requires a nonempty occurrence batch"))
  (let ((selected (make-hash-table))
        (declarations (reasoning-snapshot-relations source)))
    (for-each
     (lambda (selector)
       (unless (and (list? selector) (= (length selector) 2)
                    (symbol? (car selector)) (exact-integer? (cadr selector))
                    (< 0 (cadr selector)))
         (error "invalid source occurrence" selector))
       (let (entry (assq (car selector) declarations))
         (unless (and entry (<= (cadr selector) (length (caddr entry))))
           (error "unknown source occurrence" selector)))
       (when (hash-get selected selector) (error "duplicate source occurrence" selector))
       (hash-put! selected (candidate-copy-pairs selector) #t)) selectors)
    ;; Retain initial occurrence tokens, independently of current positions.
    ;; Both lists are private and filtered together, so duplicate row values
    ;; cannot collapse tokens or shift an already selected original support.
    (let* ((stable (map (lambda (selector)
                          (list (car selector)
                            (list-ref (source-tokens occurrences (car selector))
                                      (- (cadr selector) 1)))) selectors))
           (survivors
             (map (lambda (entry)
                    (let (kept
                          (filter-map (lambda (row token ordinal)
                                        (and (not (hash-get selected (list (car entry) ordinal)))
                                             (cons row token)))
                            (caddr entry) (source-tokens occurrences (car entry))
                            (iota (length (caddr entry)) 1)))
                      (list (car entry) (cadr entry) (map car kept) (map cdr kept)))) declarations)))
      (values
        (owned-snapshot source (+ 1 (reasoning-snapshot-generation source))
          (map (lambda (entry) (list (car entry) (cadr entry) (caddr entry))) survivors))
        (map (lambda (entry) (cons (car entry) (cadddr entry))) survivors)
        stable))))

;;; Admit a complete graph once. Positive source deletion cannot introduce
;;; new ground instances. Current positions map to private initial occurrence
;;; tokens; the admitted graph and its live restriction cover subsequent subcuts.
;; : (-> ReasoningSnapshot Datum Nat Nat WithdrawalSession)
(def (candidate-open-withdrawal-session source proposal (proof-steps 100000) (edge-limit 4096))
  (unless (reasoning-snapshot-valid? source) (error "invalid withdrawal source"))
  (unless (and (reasoning-bounded-data? proposal 16384 128)
               (exact-integer? proof-steps) (> proof-steps 0)
               (exact-integer? edge-limit) (> edge-limit 0))
    (error "invalid withdrawal session limits or proposal"))
  (let* ((snapshot (owned-snapshot source (reasoning-snapshot-generation source)
                                 (reasoning-snapshot-relations source)))
         (candidate (candidate-copy-pairs proposal))
         (spec (candidate-inspect snapshot candidate))
         (digest (candidate-content-digest candidate))
         (query (vector-ref (reasoning-candidate-query spec) 0))
         (native (gerbil-ascent-open-session (candidate-program snapshot spec)))
         (result (gerbil-ascent-session-run native)))
    (def (query-rows result)
      (filter (lambda (row) (candidate-bind-atom query row []))
              ((.ref result 'rows-of) (car query))))
    (def (open-support cut rows budget)
      (let (graph (candidate-positive-provenance cut spec digest 'complete rows budget edge-limit))
        (candidate-open-provenance-maintenance cut spec digest 'complete rows graph budget)))
    (let* ((initial-rows (query-rows result))
           ;; Only this closure owns the committed source, support, rows and tokens.
           (current (vector snapshot (open-support snapshot initial-rows proof-steps) initial-rows
                      (map (lambda (entry) (cons (car entry) (iota (length (caddr entry)) 1)))
                           (reasoning-snapshot-relations snapshot))))
           (active? #f))
      (def (observe)
        (when active? (error "withdrawal observation during transaction"))
        (let ((cut (vector-ref current 0)) (visible-rows (vector-ref current 2)))
          (.o source: (owned-snapshot cut (reasoning-snapshot-generation cut)
                                     (reasoning-snapshot-relations cut))
              rows: (candidate-copy-pairs visible-rows))))
      (def (withdraw! generation selectors budget)
        (when active? (error "reentrant withdrawal transaction"))
        (unless (and (exact-integer? generation)
                     (= generation (reasoning-snapshot-generation (vector-ref current 0)))
                     (exact-integer? budget) (> budget 0))
          (error "stale withdrawal generation or invalid budget"))
        (dynamic-wind
          (lambda () (set! active? #t))
          (lambda ()
            (let-values (((cut occurrences stable)
                          (withdraw-source-cut (vector-ref current 0) (vector-ref current 3) selectors)))
              (let-values (((support rows _work)
                            (candidate-provenance-preview-withdraw (vector-ref current 1) stable budget)))
                ;; Initial graph admission covers all ground instances. Positive
                ;; deletion only retires source seeds: DRed computes the founded
                ;; remaining closure without another native fixed-point solve.
                ;; Every allocation and bounded phase completes before one swap.
                (let (next (vector cut support (candidate-copy-pairs rows) occurrences))
                  (set! current next)))))
          (lambda () (set! active? #f)))
        (observe))
      (def (support-size)
        (when active? (error "support observation during transaction"))
        (let-values (((node-count edge-count root-count) (provenance-maintenance-size (vector-ref current 1))))
          (.o nodes: node-count edges: edge-count roots: root-count)))
      (def (compact! generation budget)
        (when active? (error "reentrant compaction transaction"))
        (unless (and (exact-integer? generation)
                     (= generation (reasoning-snapshot-generation (vector-ref current 0)))
                     (exact-integer? budget) (> budget 0))
          (error "stale compaction generation or invalid budget"))
        (dynamic-wind
          (lambda () (set! active? #t))
          (lambda ()
            (let-values (((support _work) (candidate-provenance-compact (vector-ref current 1) budget)))
              ;; Maintenance changes representation, not source generation or
              ;; public rows. A failed bounded build leaves the old owner intact.
              (let (next (vector (vector-ref current 0) support (vector-ref current 2) (vector-ref current 3)))
                (set! current next))))
          (lambda () (set! active? #f)))
        (observe))
      (validate GerbilAscentWithdrawalSessionContract
        (.o (:: @ (.ref GerbilAscentWithdrawalSessionContract 'proto))
            (.operations (.o (.observe observe) (.withdraw withdraw!)
                             (.compact compact!) (.support-size support-size))))))))

(def (withdrawal-observe session) ((.ref (.ref session '.operations) '.observe)))
(.defgeneric (withdrawal-update session generation selectors budget) slot: .withdraw)
;;; Observations detach every public pair and identity string from the owner.
;; : (-> WithdrawalSession WithdrawalObservation)
(def (candidate-withdrawal-observe session) (withdrawal-observe session))
;;; The expected generation selects current occurrences; failures publish no cut.
;; : (-> WithdrawalSession Nat SourceOccurrences Nat WithdrawalObservation)
(def (candidate-withdrawal-session! session generation selectors (budget 100000))
  (withdrawal-update (.ref session '.operations) generation selectors budget))

(.defgeneric (withdrawal-compact session generation budget) slot: .compact)
;;; Explicit positive-only maintenance preserves source generation and rows.
;; : (-> WithdrawalSession Nat Nat WithdrawalObservation)
(def (candidate-withdrawal-compact! session generation (budget 100000))
  (withdrawal-compact (.ref session '.operations) generation budget))
;;; Immutable count snapshot; this does not measure resident memory.
;; : (-> WithdrawalSession SupportSize)
(def (candidate-withdrawal-support-size session) ((.ref (.ref session '.operations) '.support-size)))
