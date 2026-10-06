;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One assigned SCC owns its transferred root/size vectors, fresh frames,
;;; physical indexes and output membership. Borrowed row roots stay persistent.
(import (only-in "component-plan.ss" positive-component-members positive-component-rules)
        (only-in "index.ss" gerbil-ascent-make-row-indexes row-indexes-rows row-indexes-advance! row-indexes-plan-actions!)
        (only-in :gerbil-ascent/core/positive-plan gerbil-ascent-run-positive-plan!))
(export make-component-snapshot gerbil-ascent-run-positive-component!)
(defstruct component-snapshot (rows sizes))

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
  (let* ((all (component-snapshot-rows snapshot))
         (all-size (component-snapshot-sizes snapshot))
         (count (vector-length all))
         (delta (make-vector count [])) (delta-size (make-vector count 0))
         (all-version (make-vector count 0)) (delta-version (make-vector count 0))
         (indexes (gerbil-ascent-make-row-indexes all delta all-size delta-size all-version delta-version
                                                  (vector-ref schema 5)))
         (rows-access (row-indexes-rows indexes))
         (advance! (row-indexes-advance! indexes))
         (seen (make-vector count #f))
         (pending (make-vector count []))
         (members (positive-component-members component))
         (rules (map (lambda (rule)
                       (vector (vector-ref rule 0) (vector-ref rule 1)
                               (make-vector (vector-ref (vector-ref rule 0) 2) #f)))
                     (positive-component-rules component))))
    (row-indexes-plan-actions! indexes
     (foldr append [] (map (lambda (rule) (vector-ref (vector-ref rule 0) 1)) rules)))
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
              (emit! atom row))))
        (for-each
         (lambda (rule)
           (let ((plan (vector-ref rule 0)) (pivots (vector-ref rule 1)) (frame (vector-ref rule 2)))
             (if first?
               (gerbil-ascent-run-positive-plan! plan frame -1 rows-access candidate! checkpoint!)
               (for-each (lambda (pivot)
                           (gerbil-ascent-run-positive-plan! plan frame pivot rows-access candidate! checkpoint!)) pivots)))) rules)
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
        (when new? (rounds #f))))))
