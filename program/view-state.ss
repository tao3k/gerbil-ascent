;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Publication over one relation owner's staged representation. The frozen
;;; total/delta and their counts move together; no concrete UF membership map.
(import :gerbil-ascent/core/relation-view
        (only-in "view-replay.ss" gerbil-ascent-small-journal-export)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-canonical-uf-storage-provider? gerbil-ascent-storage-eqrel-state?
                 gerbil-ascent-storage-view-extension! gerbil-ascent-storage-freeze-view)
        (only-in :gerbil-ascent/table/trrel-uf gerbil-ascent-trrel-uf-state gerbil-ascent-trrel-uf-insert!)
        (only-in :gerbil-ascent/table/eqrel gerbil-ascent-eqrel-state gerbil-ascent-eqrel-insert!)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-canonical-hash-index-provider?))
(export gerbil-ascent-view-journal-event gerbil-ascent-view-export-cut
        gerbil-ascent-view-relation? gerbil-ascent-stage-view!
        gerbil-ascent-commit-view! gerbil-ascent-empty-view gerbil-ascent-add-frontier
        make-view-routing-state gerbil-ascent-initialize-view-cuts! gerbil-ascent-route-view-sources!)
(def gerbil-ascent-empty-view (gerbil-ascent-explicit-view [] 0))

;; Evaluation-local buffers are shared only with their engine. Frozen cuts and
;; their source generation retain no mutable routing state after publication.
(defstruct view-routing-state (storage all delta versions names generation journals routing))
(def (initial-delta view name generation revision)
  (gerbil-ascent-view-with-export
    (gerbil-ascent-view-bind view name generation revision 'delta)
    (lambda () (reverse (gerbil-ascent-view-rows view)))))
(def (gerbil-ascent-initialize-view-cuts! relations eligible? state)
  (let ((all (view-routing-state-all state)) (delta (view-routing-state-delta state))
        (names (view-routing-state-names state)) (generation (view-routing-state-generation state))
        (journals (view-routing-state-journals state)))
    (for-each (lambda (index)
      (when (eligible? index)
        (vector-set! journals index
          (list (gerbil-ascent-view-journal-event 'source (.ref (list-ref relations index) 'rows)
            (gerbil-ascent-storage-eqrel-state? (vector-ref (view-routing-state-storage state) index)))))
        (let (frozen (gerbil-ascent-view-export-cut
                      (if (relation-view? (vector-ref all index)) (vector-ref all index)
                          gerbil-ascent-empty-view) (vector-ref journals index)))
          (vector-set! all index
            (gerbil-ascent-view-bind frozen (vector-ref names index) generation 0 'total))
          (vector-set! delta index (initial-delta frozen (vector-ref names index) generation 0)))))
      (iota (vector-length all)))))
(def (gerbil-ascent-route-view-sources! rule-plans eligible? state)
  (let ((all (view-routing-state-all state)) (delta (view-routing-state-delta state))
        (names (view-routing-state-names state)) (generation (view-routing-state-generation state))
        (journals (view-routing-state-journals state)) (routing (view-routing-state-routing state))
        (storage (view-routing-state-storage state)) (versions (view-routing-state-versions state)))
    ;; Fixed literal keys need one filter; bound variables can request many
    ;; keys. The caller admits sources and validates plans before inspection.
    (for-each (lambda (rule)
      (for-each (lambda (clause)
        (when (eq? (vector-ref clause 0) 'atom)
          (let* ((atom (vector-ref clause 1)) (index (vector-ref atom 0)))
            (when (and (eligible? index)
                       (ormap (lambda (column)
                         (not (eq? (car (list-ref (vector-ref atom 1) column)) 'literal)))
                         (vector-ref atom 2)))
              (vector-set! routing index #t))))) (vector-ref rule 1))) rule-plans)
    (for-each (lambda (index)
      (when (vector-ref routing index)
        (let (total (gerbil-ascent-view-export-cut
                      (gerbil-ascent-view-bind
                        (gerbil-ascent-storage-freeze-view (vector-ref storage index) #t)
                        (vector-ref names index) generation (vector-ref versions index) 'total)
                      (vector-ref journals index)))
          (vector-set! all index total)
          (vector-set! delta index
            (initial-delta total (vector-ref names index) generation (vector-ref versions index))))))
      (iota (vector-length all)))))
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
                                    all-version delta-version name generation events (indexed? #f))
  (let* ((revision (+ 1 (vector-ref all-version index)))
         (total (gerbil-ascent-view-export-cut
                   (gerbil-ascent-view-bind (gerbil-ascent-storage-freeze-view state indexed?)
                                            name generation revision 'total) events))
         (change (gerbil-ascent-view-with-export
                   (gerbil-ascent-view-bind frontier name generation revision 'delta)
                   (lambda () (reverse (export-events events (relation-view-count total)
                                (- (relation-view-count total) (relation-view-count frontier)) #t))))))
    (vector-set! all index total)
    (vector-set! delta index change)
    (vector-set! all-size index (relation-view-count total))
    (vector-set! delta-size index (relation-view-count change))
    (vector-set! all-version index revision)
    (vector-set! delta-version index (+ 1 (vector-ref delta-version index)))))

(defstruct view-event (kind rows eqrel?))
;; Injection spines are detached; source recovery uses its separate source log.
(def (gerbil-ascent-view-journal-event kind rows (eqrel? #f))
  (make-view-event kind (map (lambda (row) (map values row)) rows) eqrel?))
(def (gerbil-ascent-view-export-cut view events)
  (gerbil-ascent-view-with-export view
    (lambda () (export-events events (relation-view-count view) 0))))
;; Source frontiers stream directly into output. Only derived rounds need their
;; legacy batch reversal. Delta cuts replay old injections without expanding
;; their pairs, then export precisely the contiguous admitted suffix.
(def (export-events events budget skip (delta? #f))
  (or (and (not (and (pair? events) (view-event-eqrel? (car events))))
           (gerbil-ascent-small-journal-export events view-event-kind view-event-rows budget skip delta?))
      (replay-uf-events events budget skip delta?)))
(def (replay-uf-events events budget skip delta?)
      (let* ((eqrel? (and (pair? events) (view-event-eqrel? (car events))))
             (state (if eqrel? (gerbil-ascent-eqrel-state) (gerbil-ascent-trrel-uf-state)))
             (insert! (if eqrel? gerbil-ascent-eqrel-insert! gerbil-ascent-trrel-uf-insert!))
             (output []) (admitted 0))
        (for-each (lambda (event)
          (let ((batch []) (derived? (and (not delta?) (eq? (view-event-kind event) 'derived))))
            (for-each (lambda (row)
              (let* ((frontier (insert! state row budget))
                     (next (+ admitted (relation-view-count frontier))))
                (when (> next skip)
                  (when (> skip admitted) (error "ASCENT ordered delta splits an injection frontier"))
                  (let (consume
                        (if derived?
                          (lambda (stored) (set! batch (cons stored batch)))
                          (lambda (stored) (set! output (cons stored output)))))
                    (if eqrel? (for-each consume (gerbil-ascent-view-rows frontier))
                        (gerbil-ascent-for-each-row consume frontier))))
                (set! admitted next)))
              (view-event-rows event))
            ;; The legacy round walks reversed pending rows then prepends them;
            ;; source/append instead prepend each arrival directly.
            (when derived? (for-each (lambda (row) (set! output (cons row output))) batch))))
          (reverse events))
        (reverse output)))
