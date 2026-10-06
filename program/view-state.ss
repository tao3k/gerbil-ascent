;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Publication over one relation owner's staged representation. The frozen
;;; total/delta and their counts move together; no concrete UF membership map.
(import :gerbil-ascent/core/relation-view
        (only-in :gerbil-ascent/table/storage gerbil-ascent-canonical-uf-storage-provider?
                 gerbil-ascent-storage-view-extension! gerbil-ascent-storage-freeze-view)
        (only-in :gerbil-ascent/table/trrel-uf gerbil-ascent-trrel-uf-state gerbil-ascent-trrel-uf-insert!)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-canonical-hash-index-provider?))
(export gerbil-ascent-view-journal-event gerbil-ascent-view-export-cut
        gerbil-ascent-view-relation? gerbil-ascent-stage-view!
        gerbil-ascent-commit-view! gerbil-ascent-empty-view gerbil-ascent-add-frontier)
(def gerbil-ascent-empty-view (gerbil-ascent-explicit-view [] 0))
;; : (-> StorageProvider IndexProvider Boolean)
(def (gerbil-ascent-view-relation? storage index)
  (and (gerbil-ascent-canonical-uf-storage-provider? storage)
       (gerbil-ascent-canonical-hash-index-provider? index)))
;; : (-> FrozenDelta FrozenDelta FrozenDelta)
(def (gerbil-ascent-add-frontier old frontier)
  (cond ((= (gerbil-ascent-row-count frontier) 0) old)
        ((= (gerbil-ascent-row-count old) 0) frontier)
        (else (gerbil-ascent-view-union old frontier))))
;; : (-> StorageOwner Row Natural (Maybe RowCheck) FrozenDelta)
(def (gerbil-ascent-stage-view! state row budget check)
  (let (frontier (gerbil-ascent-storage-view-extension! state row budget))
    (when check (gerbil-ascent-for-each-row check frontier))
    frontier))
;; : (-> Natural StorageOwner FrozenDelta RowBuffers RowBuffers SizeBuffers SizeBuffers Versions Versions Symbol SourceGeneration Void)
(def (gerbil-ascent-commit-view! index state frontier all delta all-size delta-size
                                    all-version delta-version name generation events)
  (let* ((revision (+ 1 (vector-ref all-version index)))
         (total (gerbil-ascent-view-export-cut
                   (gerbil-ascent-view-bind (gerbil-ascent-storage-freeze-view state)
                                            name generation revision 'total) events))
         (change (gerbil-ascent-view-bind frontier name generation revision 'delta)))
    (vector-set! all index total)
    (vector-set! delta index change)
    (vector-set! all-size index (relation-view-count total))
    (vector-set! delta-size index (relation-view-count change))
    (vector-set! all-version index revision)
    (vector-set! delta-version index (+ 1 (vector-ref delta-version index)))))

(defstruct view-event (kind rows))
;; Injection spines are detached; source recovery uses its separate source log.
(def (gerbil-ascent-view-journal-event kind rows)
  (make-view-event kind (map (lambda (row) (map values row)) rows)))
(def (gerbil-ascent-view-export-cut view events)
  (gerbil-ascent-view-with-export view
    (lambda ()
      (let ((state (gerbil-ascent-trrel-uf-state)) (output []))
        (for-each (lambda (event)
          (let (batch [])
            (for-each (lambda (row)
              (gerbil-ascent-for-each-row
                (lambda (stored) (set! batch (cons stored batch)))
                (gerbil-ascent-trrel-uf-insert! state row (relation-view-count view))))
              (view-event-rows event))
            ;; The legacy round walks reversed pending rows then prepends them;
            ;; source/append instead prepend each arrival directly.
            (for-each (lambda (row) (set! output (cons row output)))
              (if (eq? (view-event-kind event) 'derived) batch (reverse batch)))))
          (reverse events))
        (reverse output)))))
