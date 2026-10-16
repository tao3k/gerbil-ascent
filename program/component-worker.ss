;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One assigned SCC owns its transferred root/size vectors, fresh frames,
;;; physical indexes and output membership. Borrowed row roots stay persistent.
(import (only-in "component-plan.ss" positive-component-members positive-component-rules)
        (only-in :std/list/list-builder with-list-builder)
        (only-in "index.ss" gerbil-ascent-make-row-indexes row-indexes-rows row-indexes-old-rows row-indexes-advance! row-indexes-plan-positive-rules!)
        (only-in :gerbil-ascent/core/positive-plan gerbil-ascent-run-positive-plan! gerbil-ascent-pure-positive-plan?))
(export make-component-snapshot gerbil-ascent-component-snapshot gerbil-ascent-run-positive-component!)
(defstruct component-snapshot (rows sizes))
(defstruct component-layout (slots members rules originals) final: #t)
(defstruct compact-component-snapshot (rows sizes layout) final: #t)

;;; Cache only immutable local relation addressing. Physical vectors, indexes,
;;; frames and membership remain private to each admitted assignment.
(def +component-layouts+
  (make-hash-table-eq weak-keys: #t lock: (make-mutex 'ascent-component-layouts)))

;;; Only pure descriptors acquire a local relation namespace. Keep compiled
;;; readers, matchers, slot extents and delta ordinals in their admitted order.
;; : (-> PurePositivePlan AtomProjection PurePositivePlan)
(def (project-component-plan plan project)
  (unless (gerbil-ascent-pure-positive-plan? plan)
    (error "ASCENT relation projection requires a pure positive plan"))
  (def (project-header header)
    (let (fresh (vector-copy header))
      (vector-set! fresh 0 (project (vector-ref header 0))) fresh))
  (vector (map project-header (vector-ref plan 0))
          (map project-header (vector-ref plan 1))
          (vector-ref plan 2) (vector-ref plan 3) (vector-ref plan 4)))

;;; The collector gives every referenced relation one dense slot in first-use order.
;;; Descriptor projection preserves body/output order and restores original
;;; descriptors at emission, before coordinator budgets and merge credit.
;; : (-> PositiveComponent ComponentLayout)
(def (compile-component-layout component)
  (let ((positions (make-hash-table-eqv)) (atoms (make-hash-table-eq))
        (originals (make-hash-table-eq)) (members #f) (rules #f))
    (let (slots
          (with-list-builder (collect!)
            (def (slot! index)
              (or (hash-get positions index)
                  (let (local (hash-length positions))
                    (hash-put! positions index local) (collect! index) local)))
            (def (project atom)
              (or (hash-get atoms atom)
                  (let (local (vector-copy atom))
                    (vector-set! local 0 (slot! (vector-ref atom 0)))
                    (hash-put! atoms atom local) (hash-put! originals local atom) local)))
            (set! members (map slot! (positive-component-members component)))
            (set! rules
              (map (lambda (rule)
                     (vector (project-component-plan (vector-ref rule 0) project)
                             (vector-ref rule 1))) (positive-component-rules component)))))
      (make-component-layout (list->vector slots) members rules originals))))

;;; Native locked primitive operations protect publication; compilation runs
;;; outside the lock and contains no assignment-owned state.
;; : (-> PositiveComponent ComponentLayout)
(def (component-workspace-layout component)
  (or (hash-get +component-layouts+ component)
      (let (fresh (compile-component-layout component))
        (hash-put! +component-layouts+ component fresh) fresh)))

;;; Ready admission copies only referenced roots and sizes from the owner's cut.
;;; Persistent row spines are borrowed; both compact vector headers are transferred.
;; : (-> PositiveComponent RowsVector Sizes CompactComponentSnapshot)
(def (gerbil-ascent-component-snapshot component rows sizes)
  (using (layout (component-workspace-layout component) :- component-layout)
    (make-compact-component-snapshot
      (vector-map (cut vector-ref rows <>) layout.slots)
      (vector-map (cut vector-ref sizes <>) layout.slots) layout)))

;; gerbil-ascent-run-positive-component!
;; : (-> PositiveComponent ProgramSchema ComponentSnapshot Emit Checkpoint Void)
;; | doc m%
;;     Close one projected SCC. The coordinator transfers fresh root and size
;;     vectors once at ready admission; the worker never reads a live frontier.
;;     Only this SCC's output relations need mutable membership tables. External
;;     inputs remain readable through private indexes without duplicating their
;;     membership. Frames belong to this assignment; emitted rows require owner
;;     merge credit before a successor may use them.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-run-positive-component! component schema snapshot emit! checkpoint!)
;;     ;; => completes the assigned SCC before reporting terminal task completion
;;     ```
;;   %
(def (gerbil-ascent-run-positive-component! component schema snapshot emit! checkpoint!)
  (if (compact-component-snapshot? snapshot)
    (run-component-workspace! schema snapshot emit! checkpoint!)
    (let (compact (gerbil-ascent-component-snapshot component (component-snapshot-rows snapshot)
                    (component-snapshot-sizes snapshot)))
      ;; Full transferred snapshots retain their existing committed-output contract.
      ;; Unwind returns only owned output slots; external source roots stay untouched.
      (dynamic-wind void
        (lambda () (run-component-workspace! schema compact emit! checkpoint!))
        (lambda ()
          (using (layout (compact-component-snapshot-layout compact) :- component-layout)
            (for-each
             (lambda (local)
               (let (global (vector-ref layout.slots local))
                 (vector-set! (component-snapshot-rows snapshot) global
                   (vector-ref (compact-component-snapshot-rows compact) local))
                 (vector-set! (component-snapshot-sizes snapshot) global
                   (vector-ref (compact-component-snapshot-sizes compact) local)))) layout.members)))))))

;;; All mutable vectors and physical indexes use the assignment's dense namespace.
;;; Global descriptors return only through emission; predecessor inputs remain borrowed.
;; : (-> ProgramSchema CompactComponentSnapshot Emit Checkpoint Void)
(def (run-component-workspace! schema (snapshot :- compact-component-snapshot) emit! checkpoint!)
  (using (layout snapshot.layout :- component-layout)
  (let* ((all snapshot.rows)
         (all-size snapshot.sizes)
         (count (vector-length all))
         (delta (make-vector count [])) (delta-size (make-vector count 0))
         (all-version (make-vector count 0)) (delta-version (make-vector count 0))
         (indexes (gerbil-ascent-make-row-indexes all delta all-size delta-size all-version delta-version
                                                  (vector-map (cut vector-ref (vector-ref schema 5) <>) layout.slots)))
         (rows-access (row-indexes-rows indexes))
         (advance! (row-indexes-advance! indexes))
         (seen (make-vector count #f))
         (pending (make-vector count []))
         (members layout.members)
         (rules (map (lambda (rule)
                       (vector (vector-ref rule 0) (vector-ref rule 1)
                               (make-vector (vector-ref (vector-ref rule 0) 2) #f)))
                     layout.rules)))
    (row-indexes-plan-positive-rules! indexes rules)
    (for-each
     (lambda (index)
       (let (table (make-hash-table))
         (for-each (lambda (row) (hash-put! table row #t)) (vector-ref all index))
         (vector-set! seen index table))) members)
    (let rounds ((first? #t))
      (let (new? #f)
        (def (candidate! atom row)
          (let* ((index (vector-ref atom 0)) (table (vector-ref seen index)))
            (unless (hash-get table row)
              (hash-put! table row #t)
              (vector-set! pending index (cons row (vector-ref pending index)))
              (set! new? #t)
              (emit! (hash-ref layout.originals atom) row))))
        (for-each
         (lambda (rule)
           (let ((plan (vector-ref rule 0)) (pivots (vector-ref rule 1)) (frame (vector-ref rule 2)))
             (if first?
               (gerbil-ascent-run-positive-plan! plan frame -1 rows-access candidate! checkpoint!)
               (for-each (lambda (pivot)
                           (gerbil-ascent-run-positive-plan! plan frame pivot rows-access candidate! checkpoint! #f (row-indexes-old-rows indexes))) pivots)))) rules)
        (for-each
         (lambda (index)
           (let* ((batch (vector-ref pending index)) (size (length batch)))
             (unless (null? batch)
               ;; Extend against the old version before publishing new roots.
               ;; Buckets prepend rows; reverse traversal preserves batch order
               ;; exactly as a rebuild over (append batch old) would do.
               (advance! index batch #t)
               (vector-set! all index (append batch (vector-ref all index)))
               (vector-set! all-size index (+ (vector-ref all-size index) size))
               (vector-set! all-version index (+ 1 (vector-ref all-version index))))
             (vector-set! delta index batch)
             ;; The delta owns this persistent batch spine. Reuse only the
             ;; candidate vector header; never clear or mutate the row spine.
             (vector-set! pending index [])
             (vector-set! delta-size index size)
             (vector-set! delta-version index (+ 1 (vector-ref delta-version index))))) members)
        (when new? (rounds #f)))))))
