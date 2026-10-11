;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/core/relation-view
        (only-in :std/iter for in-range)
        (only-in "result.ss" gerbil-ascent-make-owned-result))
(export make-execution-publication gerbil-ascent-publish-execution!)

;;; A private cut owns detached publication vectors, never live engine vectors
;;; or a public Result. Each changed execution creates its own public wrapper.
(defstruct execution-cut (snapshots sizes representations) final: #t)
(defstruct publication-state (cut) final: #t)
;;; Construction starts without a cut; only successful publication can install one.
;; : (forall (r) (-> (ExecutionPublication r)))
;; : (-> ExecutionPublication)
(def (make-execution-publication) (make-publication-state #f))


;;; The cut detaches the engine vectors while preserving lazy session row snapshots.
;;; Ordered metadata follows declaration order without temporary vector lists.
;; : (forall (row) (-> (Maybe (ExecutionCut row)) Names (RowsVector row) Sizes Deadline (ExecutionCut row)))
;; : (-> (Maybe ExecutionCut) Names RowsVector Sizes Deadline ExecutionCut)
(def (prepare-execution-cut previous names all all-size deadline)
  (let* ((count (vector-length names))
         (snapshots (make-vector count #f))
         (sizes (vector-copy all-size))
         (representations (make-vector count #f))
         (roots (and (vector? deadline) (vector-ref deadline 1)))
         (ordered (and roots (vector-ref deadline 2)))
         (previous-snapshots (and previous (execution-cut-snapshots previous)))
         (previous-sizes (and previous (execution-cut-sizes previous)))
         (previous-representations (and previous (execution-cut-representations previous))))
    (for (index (in-range count))
      (let* ((rows (vector-ref all index)) (size (vector-ref sizes index))
             (snapshot
               (if roots
                 (begin
                   (unless (eq? rows (vector-ref roots index))
                     (vector-set! ordered index
                       (if (relation-view? rows) rows
                         (gerbil-ascent-lazy-explicit-view (delay (reverse rows)) size)))
                     (vector-set! roots index rows))
                   (vector-ref ordered index))
                 (if (relation-view? rows) rows (reverse rows)))))
        (vector-set! snapshots index snapshot)
        (vector-set! representations index
          (if (and previous-snapshots
                   (eq? snapshot (vector-ref previous-snapshots index))
                   (= size (vector-ref previous-sizes index)))
            (vector-ref previous-representations index)
            (list (vector-ref names index) (if (relation-view? rows) 'rectangles 'explicit)
                  size (if (relation-view? rows) (relation-view-units rows) size))))))
    (make-execution-cut snapshots sizes representations)))

;;; Caller storage checks and staged admission precede this boundary.
;;; Revoke the metadata cache before fallible publication and adopt it only
;;; after Result construction succeeds. Clean calls retain the existing Result.
;; : (forall (r p) (-> (ExecutionPublication r) Names Arities (RowsVector r) Sizes Deadline Observation NameResolver Boolean Boolean (Values p OwnedPublication)))
;; : (-> ExecutionPublication Names Arities RowsVector Sizes Deadline Observation NameResolver Boolean Boolean (Values EvaluationResult OwnedPublication))
(def (gerbil-ascent-publish-execution! (state :- publication-state)
                                     names arity all all-size deadline observation
                                     position-of complete? session?)
  (let (previous (and session? state.cut))
    (set! state.cut #f)
    (using (cut (prepare-execution-cut previous names all all-size deadline) :- execution-cut)
      (let-values (((result publication)
                    (gerbil-ascent-make-owned-result names arity cut.snapshots cut.sizes
                      (vector->list cut.representations) observation position-of complete? session?)))
        (when session? (set! state.cut cut))
        (values result publication)))))
