;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Evaluator-owned state and the complete public Session projection.
(import (only-in :clan/poo/object .o .ref object?)
        (only-in :clan/poo/type validate)
        (only-in :gerbil-ascent/core/positive-plan current-positive-plan-cost positive-plan-cost-begin!)
        (only-in "types.ss" GerbilAscentSessionContract gerbil-ascent-fact-limit?))
(export make-engine-state engine-state-public
        gerbil-ascent-admit-engine
        engine-state-append-source! engine-state-replace-source! engine-state-run
        engine-state-run-timeout engine-state-analysis engine-state-schema
        engine-state-publication engine-state-recomputed?
        engine-state-source-additions engine-state-source-overrides)

;; This record never accepts caller-supplied methods. The evaluator below owns
;; every closure and buffer. Public Engine and Session publication still uses
;; the original full Contract; private recovery does not publish another facade.
(defstruct engine-state
  (append-source! replace-source! run run-timeout analysis schema publication
   recomputed? source-additions source-overrides) final: #t)

;; gerbil-ascent-admit-engine
;; : (forall (p r s c) (-> p Boolean Boolean (Maybe r) PositiveInteger c Boolean s Boolean Boolean (Values [Relation] [Rule] FactLimit FactLimit FactLimit)))
;; : (-> Program Boolean Boolean Reuse PositiveInteger Cancellation Boolean SourceCut Boolean Boolean (Values Relations Rules FactLimit FactLimit FactLimit))
;; | doc m%
;;     Check evaluator options, start the diagnostic collector at its original
;;     boundary, and read the declaration fields in order before creating state.
;;     Declaration fields can be observable through POO accessors.
;;     # Examples
;;     ```scheme
;;     (gerbil-ascent-admit-engine program #f #f #f 1 #f #f #f #f #f)
;;     ;; => the relations, rules and three fact limits
;;     ```
;;   %
(def (gerbil-ascent-admit-engine program session? measure-rule-times? reuse workers canceled?
                                empty-bucket-reuse? actor-sources owned-actor-inputs? retain-actor-output?)
  (unless (and (boolean? retain-actor-output?)
               (or (not retain-actor-output?)
                   (and (not session?) actor-sources owned-actor-inputs? canceled? (= workers 1))))
    (error "invalid retained Actor output ownership"))
  (unless (boolean? empty-bucket-reuse?) (error "invalid empty bucket reuse option"))
  (when (and empty-bucket-reuse? (or session? reuse (not (= workers 1)) canceled?))
    (error "empty bucket reuse requires a fresh serial scalar Set engine"))
  (when (and (current-positive-plan-cost)
             (or session? reuse (not (= workers 1)) canceled?))
    (error "native plan cost supports one fresh serial solve only"))
  (positive-plan-cost-begin! (current-positive-plan-cost))
  (unless (or (not canceled?) (procedure? canceled?))
    (error "invalid ASCENT cancellation predicate" canceled?))
  (when (and canceled? (or session? reuse measure-rule-times?))
    (error "ASCENT cancellation requires a fresh untimed evaluator"))
  (unless (and (exact-integer? workers) (> workers 0)
               (or (= workers 1) (and (not session?) (not reuse) (not measure-rule-times?))))
    (error "invalid ASCENT parallel evaluation option" workers))
  ;; The declaration constructor validates the full Core contract.
  (unless (object? program)
    (error "invalid ASCENT program" program))
  (let* ((relations (.ref program 'relations))
         (rules (.ref program 'rules))
         (input-limit (.ref program 'max-input-facts))
         (derived-limit (.ref program 'max-derived-facts))
         (output-limit (.ref program 'max-output-facts)))
    (unless (and (list? relations) (list? rules)
                 (gerbil-ascent-fact-limit? input-limit)
                 (gerbil-ascent-fact-limit? derived-limit)
                 (gerbil-ascent-fact-limit? output-limit)
                 (boolean? measure-rule-times?))
      (error "invalid ASCENT program bounds"))
    (values relations rules input-limit derived-limit output-limit)))

;; : (-> EngineState Session)
(def (engine-state-public state)
  (validate GerbilAscentSessionContract
    (.o (:: @ (.ref GerbilAscentSessionContract 'proto))
      (.append-source! (engine-state-append-source! state))
      (.source-replacement (engine-state-replace-source! state))
      (.run (engine-state-run state))
      (.run-timeout (engine-state-run-timeout state))
      (.analysis (engine-state-analysis state))
      (.schema (engine-state-schema state))
      (.native-publication (engine-state-publication state))
      (.recomputed? (engine-state-recomputed? state))
      (.source-additions (engine-state-source-additions state))
      (.source-overrides (engine-state-source-overrides state)))))
