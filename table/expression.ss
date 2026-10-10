;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; POO demand and source-slot adapter for the core binary relation kernels.

(import (only-in :clan/poo/object .o .ref .call)
        (only-in :gerbil-ascent/core/ordered-pair-set gerbil-ascent-ordered-pair-set)
        (only-in :clan/poo/trie UIntTrieSet)
        (only-in :gerbil-ascent/core/binary-relation
                 relation-view
                 native-relation-view?
                 relation-source-visitor
                 relation-compose
                 relation-delta-step
                 relation-closure
                 relation-projection
                 relation-shortest-distance-projection
                 native-path-distances native-sparse-distance-analysis
                 build-native-path-layout
                 compute-native-path-analysis
                 path-projection
                 path-distance-projection))

(export gerbil-ascent-table-expression-prototype)

;; : (-> RelationExpression (-> SourceVisitor NeighborVisitor (Maybe NeighborRows) Result) Result)
;; : (forall (a) (-> RelationExpression (-> SourceVisitor NeighborVisitor (Maybe NeighborRows) a) a))
(def (with-relation-view self consume)
  (let* ((view (.ref self 'indexed-source)) (neighbors (.ref self 'right-index)))
    (consume (vector-ref view 0) neighbors
             (and (eq? neighbors (vector-ref view 2)) (vector-ref view 1)))))

;; distance-closure-projection
;; : (forall (p) (-> (NativePathDistances p) (PairProjection p)))
;; : (-> NativePathDistances PairProjection)
;; | doc m%
;;     Publish reachability from this snapshot's already complete path analysis.
;;     Membership returns a boolean while the retained distance query stays exact.
;;
;;     # Examples
;;
;;     ```scheme
;;     (distance-closure-projection complete-distances)
;;     ;; => ordered pairs and a read-only membership query
;;     ```
;;   %
(def (distance-closure-projection (analysis :- native-path-distances))
  (let ((ordered analysis.pairs) (distance analysis.distance))
    (.o (pairs (append ordered [])) (contains? (lambda (pair) (and (distance pair) #t))))))

;; distance-snapshot-projection
;; : (forall (p) (-> (NativePathDistances p) (DistanceProjection p)))
;; : (-> NativePathDistances DistanceProjection)
;; | doc m%
;;     Detach the published row spine from private shared path analysis.
;;     Editing one public projection cannot change another projection's rows.
;;
;;     # Examples
;;
;;     ```scheme
;;     (distance-snapshot-projection complete-distances)
;;     ;; => independently owned ordered pairs and an exact distance query
;;     ```
;;   %
(def (distance-snapshot-projection (analysis :- native-path-distances))
  (let ((ordered analysis.pairs) (distance analysis.distance))
    (.o (pairs (append ordered [])) (distance-of distance))))

;;; Open POO prototype: source-pairs and radix belong to each snapshot.
;;; This signature describes extending source slots with .mix, not a direct
;;; Scheme call of the prototype value.
;; : (-> RelationSourceSlots RelationExpressionSlots)
(def gerbil-ascent-table-expression-prototype
  (.o (:: self [] source-pairs radix)
      (indexed-source (relation-view source-pairs radix))
      (right-index (vector-ref (.ref self 'indexed-source) 2))
      (native-path-layout (build-native-path-layout (.ref self 'indexed-source) (.ref self 'right-index) radix))
      (native-path-analysis (let (layout (.ref self 'native-path-layout))
                              (and layout (compute-native-path-analysis layout #f #t))))
      ;; Only the canonical private adjacency may share full path analysis.
      ;; Callback replacements and explicitly bounded calls keep their own work.
      (native-sparse-analysis
       (and (exact-integer? radix) (> radix 512)
            (let ((view (.ref self 'indexed-source)) (neighbors (.ref self 'right-index)))
              (and (native-relation-view? view) (eq? neighbors (vector-ref view 2))
                   (native-sparse-distance-analysis view radix)))))
      (compose-left
       (lambda (left-pairs)
         (with-relation-view self
           (lambda (visit-source neighbors native-neighbors)
             (relation-compose
              (if (eq? left-pairs source-pairs) visit-source (relation-source-visitor left-pairs))
              neighbors radix #f native-neighbors)))))
      (delta-step
       (lambda (frontier accumulated)
         (with-relation-view self
           (lambda (visit-source neighbors native-neighbors)
             (relation-delta-step
              (if (eq? frontier source-pairs) visit-source (relation-source-visitor frontier))
              accumulated neighbors radix native-neighbors)))))
      (closure-projection
       (let (layout (and (exact-integer? radix) (<= 32 radix 128) (.ref self 'native-path-layout)))
         (if layout
           (path-projection (vector-ref (.ref self 'native-path-analysis) 0) radix)
           (let (analysis (.ref self 'native-sparse-analysis))
             (if analysis
               (distance-closure-projection analysis)
               (with-relation-view self
                 (cut relation-closure <> <> radix #f <>)))))))
      (closure-bounded
       (lambda (max-pairs)
         (let (layout (and (exact-integer? radix) (<= 32 radix 128) (.ref self 'native-path-layout)))
           (if layout
             (path-projection (vector-ref (compute-native-path-analysis layout max-pairs #f) 0) radix)
             (with-relation-view self
               (cut relation-closure <> <> radix max-pairs <>))))))
      (closure-pairs (.ref (.ref self 'closure-projection) 'pairs))
      (closure-contains? (.ref (.ref self 'closure-projection) 'contains?))
      (closure-set (gerbil-ascent-ordered-pair-set (.ref self 'closure-pairs)))
      (shortest-distance-projection
       (let (layout (and (exact-integer? radix) (<= 32 radix 128) (.ref self 'native-path-layout)))
         (if layout
           (path-distance-projection (.ref self 'native-path-analysis) radix)
           (let (analysis (.ref self 'native-sparse-analysis))
             (if analysis
               (distance-snapshot-projection analysis)
               (with-relation-view self
                 (cut relation-shortest-distance-projection <> <> radix <>)))))))
      (shortest-distance-pairs (.ref (.ref self 'shortest-distance-projection) 'pairs))
      (shortest-distance-of (.ref (.ref self 'shortest-distance-projection) 'distance-of))
      (two-hop-pairs ((.ref self 'compose-left) source-pairs))
      (at-most-two-hop-projection
       (with-relation-view self
         (cut relation-projection <> <> radix #t <>)))
      (at-most-two-hop-contains? (.ref (.ref self 'at-most-two-hop-projection) 'contains?))
      (at-most-two-hop-pairs (.ref (.ref self 'at-most-two-hop-projection) 'pairs))))
