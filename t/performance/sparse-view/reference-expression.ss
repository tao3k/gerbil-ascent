;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; POO demand and source-slot adapter for the core binary relation kernels.

(import (only-in :clan/poo/object .o .ref .call)
        (only-in :clan/poo/trie UIntTrieSet)
        (only-in :gerbil-ascent/t/performance/sparse-view/reference-relation
                 relation-view
                 relation-source-visitor
                 relation-compose
                 relation-delta-step
                 relation-closure
                 relation-projection
                 relation-shortest-distance-projection
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
           (with-relation-view self
             (cut relation-closure <> <> radix #f <>)))))
      (closure-bounded
       (lambda (max-pairs)
         (let (layout (and (exact-integer? radix) (<= 32 radix 128) (.ref self 'native-path-layout)))
           (if layout
             (path-projection (vector-ref (compute-native-path-analysis layout max-pairs #f) 0) radix)
             (with-relation-view self
               (cut relation-closure <> <> radix max-pairs <>))))))
      (closure-pairs (.ref (.ref self 'closure-projection) 'pairs))
      (closure-contains? (.ref (.ref self 'closure-projection) 'contains?))
      (closure-set (.call UIntTrieSet .<-list (.ref self 'closure-pairs)))
      (shortest-distance-projection
       (let (layout (and (exact-integer? radix) (<= 32 radix 128) (.ref self 'native-path-layout)))
         (if layout
           (path-distance-projection (.ref self 'native-path-analysis) radix)
           (with-relation-view self
             (cut relation-shortest-distance-projection <> <> radix <>)))))
      (shortest-distance-pairs (.ref (.ref self 'shortest-distance-projection) 'pairs))
      (shortest-distance-of (.ref (.ref self 'shortest-distance-projection) 'distance-of))
      (two-hop-pairs ((.ref self 'compose-left) source-pairs))
      (at-most-two-hop-projection
       (with-relation-view self
         (cut relation-projection <> <> radix #t <>)))
      (at-most-two-hop-contains? (.ref (.ref self 'at-most-two-hop-projection) 'contains?))
      (at-most-two-hop-pairs (.ref (.ref self 'at-most-two-hop-projection) 'pairs))))
