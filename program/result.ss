;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Publish persistent ordered rows. A retained engine owns the optional cache;
;;; every publication owns its vector. Promises close only persistent row roots;
;;; unchanged roots share a promise without retaining membership or index state.
;;; Slot zero carries the invocation deadline and is never captured by results.
(import :gerbil-ascent/core/relation-view)
(export gerbil-ascent-publication-cache gerbil-ascent-publish-rows
        gerbil-ascent-snapshot-rows gerbil-ascent-snapshot-sizes
        gerbil-ascent-result-observation gerbil-ascent-public-snapshot-rows
        gerbil-ascent-visit-snapshot!)

;; gerbil-ascent-publication-cache
;;   : (-> Nat PublicationCache)
;;   | doc m%
;;       Allocate private root and promise vectors for one retained engine. The cache
;;       is never attached to a public result or shared across engines.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-publication-cache 2)
;;       ;; => private roots and ordered rows for two relations
;;       ```
;;     %
(def (gerbil-ascent-publication-cache count)
  (vector #f (make-vector count #f) (make-vector count #f)))

;; gerbil-ascent-publish-rows
;;   : (-> RowsVector PublicationCache RowsVector)
;;   | doc m%
;;       Publish a fresh vector of lazy row snapshots and reuse a promise only when
;;       the engine's persistent row root is unchanged. Engine-owned append
;;       prefixes and lattice replacement always change that root.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-publish-rows (vector '((2) (1)))
;;                                  (gerbil-ascent-publication-cache 1))
;;       ;; => a fresh vector whose promise yields '((1) (2))
;;       ```
;;     %
(def (gerbil-ascent-publish-rows all cache (sizes #f))
  (let (snapshots (make-vector (vector-length all) []))
    (publish-index! all (vector-ref cache 1) (vector-ref cache 2) snapshots 0 sizes)
    snapshots))

;; : (-> RowsVector RowsVector RowsVector RowsVector Nat Void)
(def (publish-index! all roots ordered snapshots index sizes)
  (when (< index (vector-length all))
    (let (rows (vector-ref all index))
      (unless (eq? rows (vector-ref roots index))
        (vector-set! ordered index (if (relation-view? rows) rows
                                    (gerbil-ascent-lazy-explicit-view (delay (reverse rows))
                                      (if sizes (vector-ref sizes index) (length rows)))))
        (vector-set! roots index rows))
      (vector-set! snapshots index (vector-ref ordered index)))
    (publish-index! all roots ordered snapshots (+ index 1) sizes)))

;; : (forall (a) (-> (U [a] (Promise [a])) [a]))
;; : (-> RowSnapshot Rows)
(def (gerbil-ascent-snapshot-rows rows)
  (cond ((relation-view? rows) (gerbil-ascent-view-rows rows))
        ((promise? rows) (force rows)) (else rows)))

;; Session results can seed later replacements. Public list and row spines
;; must not alias those retained roots; immutable scalar values remain shared.
(def (gerbil-ascent-public-snapshot-rows snapshot session?)
  (let (stored (gerbil-ascent-snapshot-rows snapshot))
    (if (and session? (not (relation-view? snapshot)))
      (map (lambda (row) (map identity row)) stored) stored)))

;; gerbil-ascent-snapshot-sizes
;;   : (-> Names SnapshotVector RelationSizes)
;;   | doc m%
;;       Read ordinary counts from the same memoized row views as rows-of.
;;       Name and snapshot vectors belong to this published result.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-snapshot-sizes (vector 'item) (vector '((1) (2))))
;;       ;; => '((item . 2))
;;       ```
;;     %
(def (gerbil-ascent-snapshot-sizes names snapshots)
  (map (lambda (name rows)
         (cons name (if (relation-view? rows) (relation-view-count rows)
                                (length (gerbil-ascent-snapshot-rows rows)))))
       (vector->list names) (vector->list snapshots)))

;; : (forall (a) (-> (Maybe Vector) Vector (Vector [a]) (Maybe Vector) Vector))
;; gerbil-ascent-result-observation
;;   : (-> (Maybe AffectedRelations) Names ActiveStrata (Maybe RuleTicks) Observation)
;;   | doc m%
;;       Freeze execution path, reused names, plan count and observed timings.
;;       Published metadata retains no mutable frames, ticks or prior result.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-result-observation #f '#(edge) '#(()) #f)
;;       ;; => #(stratified-semi-naive () 0 #f)
;;       ```
;;     %
(def (gerbil-ascent-result-observation affected names active rule-ticks)
  (vector
   (if affected 'stratified-dependency-invalidation 'stratified-semi-naive)
   (if affected
       (filter-map (lambda (index) (and (not (vector-ref affected index))
                                       (vector-ref names index)))
                   (iota (vector-length names))) [])
   (apply + (map length (vector->list active)))
   (and rule-ticks
        (map (lambda (ticks) (quotient (* ticks 1000000000) (jiffies-per-second)))
             (vector->list rule-ticks)))))

;; Traverse one published cut with checked ordinal keys. Invocation-local row
;; spines keep callback mutation separate from retained roots. Frozen Providers
;; retain their indexed selection instead of forcing complete ordered export.
;; : (-> RowSnapshot Natural Columns Key RowVisitor Void)
(def (gerbil-ascent-visit-snapshot! snapshot width columns key consume)
  (unless (and (list? columns) (list? key) (= (length columns) (length key))
               (andmap (lambda (column)
                         (and (exact-integer? column) (<= 0 column) (< column width))) columns))
    (error "ASCENT result selection requires in-range columns and matching keys"))
  (if (relation-view? snapshot)
    (gerbil-ascent-for-each-row consume (gerbil-ascent-view-select snapshot columns key))
    (for-each (lambda (row)
      (when (andmap (lambda (column value) (equal? (list-ref row column) value)) columns key)
        (consume (map identity row)))) (gerbil-ascent-snapshot-rows snapshot))))
