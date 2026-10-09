;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One serialized owner publishes native rows, source generation and complete
;;; grounded support together. Only positive finite candidates are admitted.
(import (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop define-type validate .defgeneric)
        (only-in :core/types PooFlowNativeObjectContract. poo-flow-predicate-contract)
        (only-in "datum.ss" candidate-copy-pairs reasoning-bounded-data?)
        (only-in "types.ss" reasoning-snapshot-valid? reasoning-snapshot-relations
                 reasoning-snapshot-identity reasoning-snapshot-generation
                 reasoning-candidate-query reasoning-candidate-facts)
        (only-in "reasoning.ss" reasoning-source-snapshot candidate-content-digest)
        (only-in "program.ss" candidate-inspect candidate-program)
        (only-in "funs.ss" candidate-bind-atom candidate-same-row-set?)
        (only-in "provenance-graph.ss" candidate-positive-provenance
                 candidate-open-provenance-maintenance
                 candidate-provenance-preview-withdraw)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session
                 gerbil-ascent-session-run gerbil-ascent-session-replace-sources!))
(export candidate-open-withdrawal-session candidate-withdrawal-observe
        candidate-withdrawal-session! GerbilAscentWithdrawalSessionContract)

(define-type (GerbilAscentWithdrawalSessionContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/grounded-withdrawal-session
  proto: (.o)
  responsibilities:
  (.o .observe: (poo-flow-predicate-contract 'ascent/observe procedure? (lambda (_v _c) []))
      .withdraw: (poo-flow-predicate-contract 'ascent/withdraw procedure? (lambda (_v _c) []))))

;;; Copy source identity as well as declaration spines: strings are mutable.
;; : (-> ReasoningSnapshot Nat SourceDeclarations ReasoningSnapshot)
(def (owned-snapshot source generation declarations)
  (let (id (reasoning-snapshot-identity source))
    (reasoning-source-snapshot (if (string? id) (string-copy id) id)
                              generation declarations)))

;;; Selectors refer to one-based occurrences in the CURRENT source cut. All
;;; selectors are checked before removal; duplicate row values remain distinct.
;; : (-> ReasoningSnapshot SourceOccurrences ReasoningSnapshot)
(def (withdraw-source-cut source selectors)
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
    (owned-snapshot source (+ 1 (reasoning-snapshot-generation source))
      (map (lambda (entry)
             (list (car entry) (cadr entry)
               (let loop ((rows (caddr entry)) (ordinal 1))
                 (if (null? rows) []
                   (let (rest (loop (cdr rows) (+ ordinal 1)))
                     (if (hash-get selected (list (car entry) ordinal)) rest
                       (cons (car rows) rest))))))) declarations))))

;;; Constructor and each transaction replay a complete graph at the prospective
;;; cut. This rebinds occurrence ordinals and covers all actual alternatives;
;;; retaining the previous graph after row removal would mislabel later cuts.
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
           ;; Only this closure owns the native Session and committed triple.
           (current (vector snapshot (open-support snapshot initial-rows proof-steps) initial-rows))
           (active? #f))
      (def (observe)
        (when active? (error "withdrawal observation during transaction"))
        (let (cut (vector-ref current 0))
          (.o source: (owned-snapshot cut (reasoning-snapshot-generation cut)
                                     (reasoning-snapshot-relations cut))
              rows: (candidate-copy-pairs (vector-ref current 2)))))
      (def (withdraw! generation selectors budget)
        (when active? (error "reentrant withdrawal transaction"))
        (unless (and (exact-integer? generation)
                     (= generation (reasoning-snapshot-generation (vector-ref current 0)))
                     (exact-integer? budget) (> budget 0))
          (error "stale withdrawal generation or invalid budget"))
        (dynamic-wind
          (lambda () (set! active? #t))
          (lambda ()
            (let* ((cut (withdraw-source-cut (vector-ref current 0) selectors))
                   (next #f))
              (let-values (((_preview rows _work)
                            (candidate-provenance-preview-withdraw (vector-ref current 1) selectors budget)))
                ;; Prospective certificate admission happens before native publication.
                (let* ((support (open-support cut rows budget))
                       (replacements
                         (map (lambda (entry)
                                (cons (car entry)
                                  (append (caddr entry)
                                    (map (lambda (fact) (vector-ref fact 1))
                                      (filter (lambda (fact) (eq? (vector-ref fact 0) (car entry)))
                                              (reasoning-candidate-facts spec))))))
                              (reasoning-snapshot-relations cut))))
                  (gerbil-ascent-session-replace-sources! native replacements
                    (lambda (result)
                      (let (actual (query-rows result))
                        (unless (candidate-same-row-set? rows actual)
                          (error "withdrawal preview and native result disagree"))
                        ;; Allocate every published owner before the native commit.
                        (set! next (vector cut support (candidate-copy-pairs actual)))
                        #t)))
                  (set! current next)))))
          (lambda () (set! active? #f)))
        (observe))
      (validate GerbilAscentWithdrawalSessionContract
        (.o (:: @ (.ref GerbilAscentWithdrawalSessionContract 'proto))
            (.observe observe) (.withdraw withdraw!))))))

(def (withdrawal-observe session) ((.ref session '.observe)))
(.defgeneric (withdrawal-update session generation selectors budget) slot: .withdraw)
;;; Observations detach every public pair and identity string from the owner.
;; : (-> WithdrawalSession WithdrawalObservation)
(def (candidate-withdrawal-observe session) (withdrawal-observe session))
;;; The expected generation selects current occurrences; failures publish no cut.
;; : (-> WithdrawalSession Nat SourceOccurrences Nat WithdrawalObservation)
(def (candidate-withdrawal-session! session generation selectors (budget 100000))
  (withdrawal-update session generation selectors budget))
