;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Completed-closure reuse admission and engine-local rule activation.
(import (only-in :gerbil-ascent/program/activation gerbil-ascent-activate-plans)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/core/rule-semantics gerbil-ascent-lattice-key)
        (only-in :gerbil-ascent/t/performance/source-materialization/reference-selection gerbil-ascent-update-selection
                 gerbil-ascent-update-active-plans gerbil-ascent-select-rule-plans))
(export gerbil-ascent-prepare-native-reuse gerbil-ascent-reuse-active-rules
        gerbil-ascent-activate-rules gerbil-ascent-activate-selected-rules
        native-reuse? native-reuse-result native-reuse-affected
        gerbil-ascent-seed-native-reuse! make-closure-seed-state)

;;; Only completed native snapshots may seed an update. The capsule is private
;;; to this module; checked Session owns the previous and prospective inputs.
;; native-reuse
;; : (forall (r a) (-> r a (NativeReuse r a)))
;; : (-> EvaluationResult AffectedRelations NativeReuse)
;; | doc m%
;;     Carry the admitted completed result and affected relation mask privately.
;;
;;     # Examples
;;
;;     ```scheme
;;     (make-native-reuse completed affected)
;;     ;; => an internal capsule after completed-result admission
;;     ```
;;   %
(defstruct native-reuse (result affected))

;; gerbil-ascent-prepare-native-reuse
;; : (forall (p r a c) (-> p p r a (Maybe c)))
;; : (-> SourceSnapshot Program EvaluationResult Analysis (Maybe NativeReuse))
;; | doc m%
;;     Admit a completed closure for stable source-only updates. The affected
;;     dependency closure includes positive, negative and aggregate reads.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-prepare-native-reuse previous candidate completed analysis)
;;     ;; => a private reuse capsule, or #f for unsupported callbacks/providers
;;     ```
;;   %
(def (gerbil-ascent-prepare-native-reuse previous candidate completed analysis)
  (unless (.ref completed 'finished) (error "cannot reuse a partial closure"))
  (let (affected (gerbil-ascent-update-selection previous candidate analysis))
    (and affected (make-native-reuse completed affected))))

;; gerbil-ascent-activate-rules
;; : (forall (a r) (-> a (Vector [r])))
;; : (-> Analysis ActiveRulesByStratum)
;; | doc m%
;;     Instantiate cached immutable activation metadata with engine-local frames.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-activate-rules analysis)
;;     ;; => all rules with fresh mutable frames, leaving analysis unchanged
;;     ```
;;   %
(def (gerbil-ascent-activate-rules analysis)
  (gerbil-ascent-activate-plans (vector-ref analysis 5)))

;; : (forall (a r) (-> a Vector (Vector [r])))
;; gerbil-ascent-activate-selected-rules
;;   : (-> Analysis AffectedRelations ActiveRulesByStratum)
;;   | doc m%
;;       Select immutable affected plans before creating engine-owned frames.
;;       No frame is allocated for discarded rules or unselected output heads.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-activate-selected-rules analysis affected)
;;       ;; => fresh frames only for the selected plans
;;       ```
;;     %
(def (gerbil-ascent-activate-selected-rules analysis affected)
  (gerbil-ascent-activate-plans
   (gerbil-ascent-select-rule-plans (vector-ref analysis 5) affected)))

;; gerbil-ascent-reuse-active-rules
;; : (forall (r c) (-> (Vector [r]) (Maybe c) (Vector [r])))
;; : (-> ActiveRulesByStratum (Maybe NativeReuse) ActiveRulesByStratum)
;; | doc m%
;;     Select affected heads while retaining the complete activation for
;;     later source appends. Partial heads receive their own compiled frames.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-reuse-active-rules all-rules #f)
;;     ;; => all-rules, with no filtering or new frames
;;     ```
;;   %
(def (gerbil-ascent-reuse-active-rules full-active-by-stratum reuse)
  (if (not reuse)
    full-active-by-stratum
    (gerbil-ascent-update-active-plans
     full-active-by-stratum (native-reuse-affected reuse))))

;;; A private frame groups buffers owned by the prospective engine. Neither
;;; the completed result nor the cached analysis retains this mutable frame.
;; closure-seed-state
;; : (forall (r m k) (-> (Vector [r]) (Vector m) (Vector [r]) Vector Vector (Vector k) (ClosureSeedState r m k)))
;; : (-> AllRows Membership DeltaRows AllSizes DeltaSizes LatticeRows ClosureSeedState)
(defstruct closure-seed-state (all seen delta all-size delta-size lattice-rows))

;; gerbil-ascent-seed-native-reuse!
;; : (forall (r s b) (-> r s b Nat Nat Nat Nat))
;; : (-> NativeReuse Schema ClosureSeedState Nat Nat Nat Nat)
;; | doc m%
;;     Admit unaffected completed relations into this engine's fresh buffers.
;;     Return the unique derived fact count after row and budget checks. Storage
;;     eligibility is established by update-selection before capsule creation.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-seed-native-reuse! reuse schema buffers 4 20 24)
;;     ;; => the derived count seeded from independent completed components
;;     ```
;;   %
(def (gerbil-ascent-seed-native-reuse! reuse schema buffers
                                      source-materialized-count derived-limit output-limit)
  (let ((names (vector-ref schema 1))
        (arity (vector-ref schema 2))
        (field-checkers (vector-ref schema 3))
        (lattice-joins (vector-ref schema 7))
        (all (closure-seed-state-all buffers))
        (seen (closure-seed-state-seen buffers))
        (delta (closure-seed-state-delta buffers))
        (all-size (closure-seed-state-all-size buffers))
        (delta-size (closure-seed-state-delta-size buffers))
        (lattice-rows (closure-seed-state-lattice-rows buffers))
        (count (vector-length (vector-ref schema 1)))
        (derived-count 0))
    (when reuse
      (unless (native-reuse? reuse) (error "invalid native reuse capsule"))
      (let seed ((index 0))
        (when (< index count)
          (unless (vector-ref (native-reuse-affected reuse) index)
            (let* ((rows ((.ref (native-reuse-result reuse) 'rows-of) (vector-ref names index)))
                   (base (vector-ref all index))
                   (check (vector-ref field-checkers index))
                   ;; Set admission already populated this source membership.
                   ;; Lattice admission joins source rows by key instead, so
                   ;; build membership from its final joined source rows.
                   (base-present
                    (and (not check)
                     (if (vector-ref lattice-joins index)
                      (let (membership (make-hash-table))
                        (for-each (lambda (row) (hash-put! membership row #t))
                                  base)
                        membership)
                      (vector-ref seen index))))
                   (present (make-hash-table)))
              (for-each
               (lambda (row)
                 (unless (and (list? row) (= (length row) (vector-ref arity index)))
                   (error "invalid completed reuse row"))
                 (when check (check row))
                 (unless (hash-get present row)
                   (hash-put! present row #t)
                   ;; User field callbacks retain the original equality walk.
                   (unless (if base-present (hash-get base-present row) (member row base))
                     (set! derived-count (+ derived-count 1))))) rows)
              (when (or (> derived-count derived-limit)
                        (> (+ source-materialized-count derived-count) output-limit))
                (error "ASCENT reused closure fact budget exceeded"))
              (when (vector-ref lattice-joins index)
                (let (keyed (make-hash-table))
                  (for-each (lambda (row) (hash-put! keyed (gerbil-ascent-lattice-key row) row)) rows)
                  (vector-set! lattice-rows index keyed)))
              (vector-set! all index (reverse rows))
              (vector-set! seen index present)
              (vector-set! delta index (vector-ref all index))
              (vector-set! all-size index (length rows))
              (vector-set! delta-size index (length rows))))
          (seed (+ index 1)))))
    derived-count))
