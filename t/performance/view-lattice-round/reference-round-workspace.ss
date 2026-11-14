;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Set/hash rounds own two sparse sets: retained nonempty deltas and this
;;; invocation's candidate destinations. No row spine or callback lives here.
(import (only-in :std/iter for for/fold in-range)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-canonical-hash-index-provider?)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-canonical-set-storage-provider?)
        (only-in :std/list/list-builder with-list-builder))
(export make-round-layout round-layout-source! make-round-work
        round-work-write! round-work-reset! round-work-commit-indices
        round-work-complete!)

(defstruct round-layout-state (strata frontier) final: #t)
(defstruct round-work-state (layout writes) final: #t)

;; : (-> Strata DeltaSizes StorageProviders IndexProviders LatticeJoins (Maybe RoundLayout))
(def (make-round-layout strata sizes providers indexes joins)
  (and (> (vector-length strata) 1)
       (for/fold (native? #t) (slot (in-range (vector-length strata)))
         (and native? (not (vector-ref joins slot))
              (gerbil-ascent-canonical-set-storage-provider? (vector-ref providers slot))
              (gerbil-ascent-canonical-hash-index-provider? (vector-ref indexes slot))))
       (let ((groups (make-hash-table-eqv)) (frontier (make-hash-table-eqv)))
         (for (index (in-range (vector-length strata)))
           (let (stratum (vector-ref strata index))
             (hash-put! groups stratum (cons index (or (hash-get groups stratum) []))))
           (when (> (vector-ref sizes index) 0) (hash-put! frontier index #t)))
         (make-round-layout-state groups frontier))))

;; : (-> (Maybe RoundLayout) RelationIndex Void)
(def (round-layout-source! layout index)
  (when layout (using (layout :- round-layout-state) (hash-put! layout.frontier index #t))))

;; : (-> (Maybe RoundLayout) (Maybe RoundWork))
(def (make-round-work layout)
  (and layout (make-round-work-state layout (make-hash-table-eqv))))

;; Record only effective candidates, after row/membership admission succeeds.
;; : (-> (Maybe RoundWork) RelationIndex Void)
(def (round-work-write! work index)
  (when work (using (work :- round-work-state) (hash-put! work.writes index #t))))

;; Seed a stratum once; reset only the previous frontier plus nonempty totals.
;; Empty unchanged lanes retain their version-owned native index entries.
;; : (-> RoundWork Natural Boolean AllSizes DeltaSizes (-> RelationIndex Void) Void)
(def (round-work-reset! (work :- round-work-state) stratum seed? sizes deltas reset!)
  (using (layout work.layout :- round-layout-state)
    (let (selected (hash-copy layout.frontier))
      (when seed?
        (for-each (lambda (index)
                    (when (> (vector-ref sizes index) 0) (hash-put! selected index #t)))
                  (or (hash-get layout.strata stratum) [])))
      ;; Retain the old frontier if any reset operation fails.
      (for-each reset! (list-sort < (hash-keys selected)))
      (hash-clear! layout.frontier)
      (for-each (lambda (index)
                  (when (> (vector-ref deltas index) 0) (hash-put! layout.frontier index #t)))
                (hash-keys selected)))))

;; Ascending declaration order preserves commit/index publication order.
;; The old frontier is included even when no new candidate replaces its delta.
;; : (-> RoundWork [RelationIndex])
(def (round-work-commit-indices (work :- round-work-state))
  (using (layout work.layout :- round-layout-state)
    (list-sort <
      (with-list-builder (collect!)
        (hash-for-each (lambda (index _) (collect! index)) layout.frontier)
        (hash-for-each (lambda (index _)
                         (unless (hash-get layout.frontier index) (collect! index))) work.writes)))))

;; Advance the sparse frontier only after the entire owner commit succeeds.
;; This invocation's candidates never survive an exception or timeout return.
;; : (-> RoundWork DeltaSizes Void)
(def (round-work-complete! (work :- round-work-state) sizes)
  (using (layout work.layout :- round-layout-state)
    (hash-clear! layout.frontier)
    (hash-for-each (lambda (index _)
                   (when (> (vector-ref sizes index) 0) (hash-put! layout.frontier index #t))) work.writes)
    (hash-clear! work.writes)))
