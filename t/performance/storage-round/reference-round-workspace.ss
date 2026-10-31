;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Native Set/view/lattice rounds retain nonempty deltas and this invocation's
;;; touched destinations. Slot marks deduplicate an ordered write list without
;;; a second hash owner. No row spine or callback lives here.
(import (only-in :std/iter for for/fold in-range)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-canonical-hash-index-provider?)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-canonical-set-storage-provider?
                 gerbil-ascent-canonical-view-storage-provider? gerbil-ascent-storage-admit-state!)
        (only-in :std/list/list-builder with-list-builder))
(export make-round-layout round-layout-source! make-round-work
        round-work-write! round-work-reset! round-work-commit-indices
        round-work-complete! round-work-admit-states!
        round-layout-view-staging? round-layout-lattice-staging?)

(defstruct round-layout-state (strata frontier width views? lattices?) final: #t)
(defstruct round-work-state (layout writes marked) final: #t)

;; : (-> Strata DeltaSizes StorageProviders IndexProviders LatticeJoins (Maybe RoundLayout))
(def (make-round-layout strata sizes providers indexes joins)
  (let ((views? #f) (lattices? #f))
    (and (> (vector-length strata) 1)
         (for/fold (native? #t) (slot (in-range (vector-length strata)))
           (and native?
                (gerbil-ascent-canonical-hash-index-provider? (vector-ref indexes slot))
                (cond
                 ;; Lattices own the evaluator's key table; they have no storage provider.
                 ((and (vector-ref joins slot) (not (vector-ref providers slot)))
                  (set! lattices? #t) #t)
                 ((gerbil-ascent-canonical-set-storage-provider? (vector-ref providers slot))
                  #t)
                 ((and (not (vector-ref joins slot))
                       (gerbil-ascent-canonical-view-storage-provider? (vector-ref providers slot)))
                  (set! views? #t) #t)
                 (else #f))))
         (let ((groups (make-hash-table-eqv)) (frontier (make-hash-table-eqv)))
           (for (index (in-range (vector-length strata)))
             (let (stratum (vector-ref strata index))
               (hash-put! groups stratum (cons index (or (hash-get groups stratum) []))))
             (when (> (vector-ref sizes index) 0) (hash-put! frontier index #t)))
           (make-round-layout-state groups frontier (vector-length strata) views? lattices?)))))

;; Unsupported providers preserve all staging and version contracts.
;; : (-> (Maybe RoundLayout) Boolean)
(def (round-layout-view-staging? layout)
  (or (not layout) (using (layout :- round-layout-state) layout.views?)))
;; : (-> (Maybe RoundLayout) Boolean)
(def (round-layout-lattice-staging? layout)
  (or (not layout) (using (layout :- round-layout-state) layout.lattices?)))

;; : (-> (Maybe RoundLayout) RelationIndex Void)
(def (round-layout-source! layout index)
  (when layout (using (layout :- round-layout-state) (hash-put! layout.frontier index #t))))

;; : (-> (Maybe RoundLayout) (Maybe RoundWork))
(def (make-round-work layout)
  (and layout
       (using (layout :- round-layout-state)
         (make-round-work-state layout [] (make-vector layout.width #f)))))

;; Record effective candidates and every attempted native view extension.
;; A no-op view extension still requires state admission after the owner commit.
;; : (-> (Maybe RoundWork) RelationIndex Void)
(def (round-work-write! work index)
  (when work
    (using (work :- round-work-state)
      (unless (vector-ref work.marked index)
        (vector-set! work.marked index #t)
        (set! work.writes (cons index work.writes))))))

;; Seed a stratum once; reset only the previous frontier plus nonempty totals.
;; Empty unchanged lanes retain their version-owned native index entries.
;; : (-> RoundWork Natural Boolean AllSizes DeltaSizes (-> RelationIndex Void) Void)
(def (round-work-reset! (work :- round-work-state) stratum seed? sizes deltas reset!)
  (using (layout work.layout :- round-layout-state)
    (let (selected
          (with-list-builder (collect!)
            (hash-for-each (lambda (index _) (collect! index)) layout.frontier)
            (when seed?
              (for-each (lambda (index)
                          (when (and (> (vector-ref sizes index) 0)
                                     (not (hash-get layout.frontier index)))
                            (collect! index)))
                        (or (hash-get layout.strata stratum) [])))))
      ;; Retain the old frontier if any reset operation fails.
      (for-each reset! (list-sort < selected))
      (hash-clear! layout.frontier)
      (for-each (lambda (index)
                  (when (> (vector-ref deltas index) 0) (hash-put! layout.frontier index #t)))
                selected))))

;; Ascending declaration order preserves commit/index publication order.
;; The old frontier is included even when no new candidate replaces its delta.
;; : (-> RoundWork [RelationIndex])
(def (round-work-commit-indices (work :- round-work-state))
  (using (layout work.layout :- round-layout-state)
    (list-sort <
      (with-list-builder (collect!)
        (hash-for-each (lambda (index _) (collect! index)) layout.frontier)
        (for-each (lambda (index)
                    (unless (hash-get layout.frontier index) (collect! index))) work.writes)))))

;; Advance the sparse frontier only after the entire owner commit succeeds.
;; This invocation's candidates never survive an exception or timeout return.
;; : (-> RoundWork DeltaSizes Void)
(def (round-work-complete! (work :- round-work-state) sizes)
  (using (layout work.layout :- round-layout-state)
    (hash-clear! layout.frontier)
    (for-each (lambda (index)
                (when (> (vector-ref sizes index) 0) (hash-put! layout.frontier index #t))
                (vector-set! work.marked index #f)) work.writes)
    (set! work.writes [])))

;; View staging, including no-op extension, sets private ownership pending.
;; Admit those owners only after every row/index/view cut has been published.
;; : (-> RoundWork StorageStates Void)
(def (round-work-admit-states! (work :- round-work-state) states)
  (using (layout work.layout :- round-layout-state)
    (when layout.views?
      (for-each (lambda (index) (gerbil-ascent-storage-admit-state! (vector-ref states index)))
                work.writes))))
