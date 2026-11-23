;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Completed-closure reuse admission and engine-local rule activation.
(import (only-in "activation.ss" gerbil-ascent-activate-plans)
        (only-in :std/func @compose1)
        (only-in :gerbil-ascent/core/execution-control current-ascent-execution-control
                 ascent-execution-checkpoint!)
        (only-in "result.ss" gerbil-ascent-publication-reader gerbil-ascent-publication-size
                 gerbil-ascent-result-complete? gerbil-ascent-materialize-result)
        (only-in "scheme-checked.ss" relational-scalar?)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-canonical-set-storage-provider?)
        (only-in :gerbil-ascent/core/rule-semantics gerbil-ascent-lattice-key)
        (only-in "update-selection.ss" gerbil-ascent-update-selection
                 gerbil-ascent-update-active-plans gerbil-ascent-select-rule-plans))
(export gerbil-ascent-prepare-session-reuse gerbil-ascent-reuse-active-rules
        gerbil-ascent-activate-rules gerbil-ascent-activate-selected-rules
        session-reuse? session-reuse-result session-reuse-affected
        gerbil-ascent-seed-session-reuse! make-closure-seed-state
        gerbil-ascent-prepare-parent-reuse gerbil-ascent-ensure-reuse-membership!)

;;; Only completed native snapshots may seed an update. The capsule is private
;;; to this module; checked Session owns the previous and prospective inputs.
;; session-reuse
;; : (forall (r a f p s) (-> r a f p s (NativeReuse r a f p s)))
;; : (-> EvaluationResult AffectedRelations (Maybe RowReader) (Maybe OwnedPublication) SourceOnlyRelations NativeReuse)
;; | doc m%
;;     Carry the admitted completed result and affected relation mask privately.
;;
;;     # Examples
;;
;;     ```scheme
;;     (make-session-reuse completed affected)
;;     ;; => an internal capsule after completed-result admission
;;     ```
;;   %
(defstruct session-reuse (result affected reader publication source-only parent?))

;;; A relation with no rule head can contain only admitted source occurrences.
;;; Keep every written relation conservative, including inactive/self rules.
;; : (forall (a) (-> a Natural (Vector Boolean)))
;; : (-> Analysis Natural SourceOnlyRelations)
(def (source-only-relations analysis count)
  (let (source-only (make-vector count #t))
    (for-each (lambda (rule)
                (for-each (lambda (head) (vector-set! source-only (vector-ref head 0) #f))
                          (vector-ref rule 0))) (vector-ref analysis 2))
    source-only))

;; gerbil-ascent-prepare-session-reuse
;; : (forall (p r a c s o) (-> (Vector (SourceLog r)) p r a (Maybe s) (Maybe o) (Maybe c)))
;; : (-> SourceLogVector Program EvaluationResult Analysis (Maybe SourceSnapshot) (Maybe OwnedPublication) (Maybe NativeReuse))
;; | doc m%
;;     Admit a completed closure for stable source-only updates. The affected
;;     dependency closure includes positive, negative and aggregate reads.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-prepare-session-reuse previous candidate completed analysis)
;;     ;; => a private reuse capsule, or #f for unsupported callbacks/providers
;;     ```
;;   %
(def (gerbil-ascent-prepare-session-reuse previous candidate completed analysis
                                       (source-cut #f) (publication #f))
  (prepare-reuse previous candidate completed analysis source-cut publication #f))

;; Only the choice Session's restoration of its own committed cut can
;; skip revalidating immutable Set rows. Replacements use the ordinary owner.
(def (gerbil-ascent-prepare-parent-reuse previous candidate completed analysis source-cut publication)
  (prepare-reuse previous candidate completed analysis source-cut publication
    (not (current-ascent-execution-control))))

(def (prepare-reuse previous candidate completed analysis source-cut publication parent?)
  (unless (gerbil-ascent-result-complete? completed) (error "cannot reuse a partial closure"))
  ;; Root evidence specializes only source equality; completed/eligible
  ;; admission and transitive dependency closure remain authoritative.
  (alet (affected (gerbil-ascent-update-selection previous candidate analysis source-cut))
    (let (reader (gerbil-ascent-publication-reader publication completed))
      (make-session-reuse completed affected reader publication
        (and publication (source-only-relations analysis (vector-length previous)))
        (and reader parent?)))))

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
(def gerbil-ascent-activate-rules
  (@compose1 gerbil-ascent-activate-plans (cut vector-ref <> 5)))

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
    (using (reuse :- session-reuse)
      (gerbil-ascent-update-active-plans full-active-by-stratum reuse.affected))))

;;; A private frame groups buffers owned by the prospective engine. Neither
;;; the completed result nor the cached analysis retains this mutable frame.
;; closure-seed-state
;; : (forall (r m k) (-> (Vector [r]) (Vector m) (Vector [r]) Vector Vector (Vector k) (ClosureSeedState r m k)))
;; : (-> AllRows Membership DeltaRows AllSizes DeltaSizes LatticeRows ClosureSeedState)
(defstruct closure-seed-state (all seen delta all-size delta-size lattice-rows))

(def (seed-base-membership schema index base seen check join)
  (cond
    ((and (not check) (not join)) seen)
    ((or (not check)
         (and (not join)
              (gerbil-ascent-canonical-set-storage-provider? (vector-ref (vector-ref schema 9) index))
              (> (vector-length schema) 10)
              ;; Inspect the predicate list captured by the executing checker.
              ;; A declaration getter can now refer to a different list.
              (let (predicates (vector-ref (vector-ref schema 10) index))
                (and (pair? predicates) (list? predicates)
                     (andmap (lambda (predicate)
                               (or (eq? predicate relational-scalar?) (eq? predicate exact-integer?)))
                             predicates)))))
     ;; Build from the current base after obtaining the completed rows.
     ;; Earlier admission can invoke host code.
     (let (membership (if check (make-hash-table size: (hash-length seen)) (make-hash-table)))
       (for-each (lambda (row) (hash-put! membership row #t)) base)
       membership))
    (else #f)))

;; An engine with a deferred Set still owns its complete committed row
;; spine. The first membership consumer builds a private table from it.
(def deferred-reuse-membership (list 'deferred-reuse-membership))

(def (gerbil-ascent-ensure-reuse-membership! all seen index)
  (let (present (vector-ref seen index))
    (if (eq? present deferred-reuse-membership)
      (let ((fresh (make-hash-table)) (controlled? (current-ascent-execution-control)))
        (for-each (lambda (row)
                    (when controlled? (ascent-execution-checkpoint!))
                    (hash-put! fresh row #t))
                  (vector-ref all index))
        (vector-set! seen index fresh)
        fresh)
      present)))

;; gerbil-ascent-seed-session-reuse!
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
;;     (gerbil-ascent-seed-session-reuse! reuse schema buffers 4 20 24)
;;     ;; => the derived count seeded from independent completed components
;;     ```
;;   %
(def (gerbil-ascent-seed-session-reuse! reuse schema buffers
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
    (def (check-derived-budget!)
      (when (or (> derived-count derived-limit)
                (> (+ source-materialized-count derived-count) output-limit))
        (error "ASCENT reused closure fact budget exceeded")))
    (def (seed-membership! index rows base join)
      (let* ((check (vector-ref field-checkers index))
             (base-present (seed-base-membership schema index base (vector-ref seen index) check join))
             (present (if (and (null? base) (null? rows) (not join))
                          (vector-ref seen index)
                          (make-hash-table))))
        (for-each
         (lambda (row)
           (unless (and (list? row) (= (length row) (vector-ref arity index)))
             (error "invalid completed reuse row"))
           (when check (check row))
           (unless (hash-get present row)
             (hash-put! present row #t)
             ;; User field callbacks retain the original equality walk.
             (unless (if base-present (hash-get base-present row) (member row base))
               (set! derived-count (+ derived-count 1)))))
         rows)
        (check-derived-budget!)
        (when join
          (let (keyed (make-hash-table))
            (for-each (lambda (row) (hash-put! keyed (gerbil-ascent-lattice-key row) row)) rows)
            (vector-set! lattice-rows index keyed)))
        (vector-set! seen index present)
        (length rows)))
    (when reuse
      (unless (session-reuse? reuse) (error "invalid native reuse capsule"))
      (let seed ((index 0))
        (when (< index count)
          (unless (vector-ref (session-reuse-affected reuse) index)
            (let* ((name (vector-ref names index))
                   (join (vector-ref lattice-joins index))
                   (published-size
                    (gerbil-ascent-publication-size
                     (session-reuse-publication reuse) (session-reuse-result reuse) name)))
              ;; Fresh source admission already owns the exact source-only
              ;; membership when the published occurrence count agrees.
              (unless (and (session-reuse-source-only reuse) (not join)
                           (vector-ref (session-reuse-source-only reuse) index)
                           (eqv? (vector-ref all-size index) published-size))
                (let* ((rows ((or (session-reuse-reader reuse)
                                  (.ref (gerbil-ascent-materialize-result (session-reuse-result reuse)) 'rows-of))
                              name))
                       (base (vector-ref all index))
                       (size
                        (if (and (session-reuse-parent? reuse) (null? base) (not join) published-size
                                 (gerbil-ascent-canonical-set-storage-provider?
                                  (vector-ref (vector-ref schema 9) index)))
                          ;; This checked parent has unique Set rows and no
                          ;; base facts here. Every published row is derived.
                          (begin
                            (set! derived-count (+ derived-count published-size))
                            (check-derived-budget!)
                            (unless (zero? published-size)
                              (vector-set! seen index deferred-reuse-membership))
                            published-size)
                          (seed-membership! index rows base join)))
                       (root (reverse rows)))
                  (vector-set! all index root)
                  (vector-set! delta index root)
                  (vector-set! all-size index size)
                  (vector-set! delta-size index size)))))
          (seed (+ index 1)))))
    derived-count))
