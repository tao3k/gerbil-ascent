;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Tarjan over dense vertex IDs. Components are returned in source-before-
;;; target order; callers retain ownership of their edge labels and metadata.
;;; Numeric specialization boundary: IDs and discovery indices are bounded
;;; by vector-length, including the final count sentinel. Checked fx operations
;;; apply only to these dense traversal counters, never to caller edge labels.
(export gerbil-ascent-graph-components gerbil-ascent-graph-close!)

(defstruct graph-frame (node remaining parent) final: #t)

;; gerbil-ascent-graph-close!
;;   : (-> (Vector [Nat]) (Vector Boolean) Void)
;;   : (-> DenseAdjacency (Vector Boolean) Void)
;;   | doc m%
;;       Close an invocation-owned selection over read-only dense adjacency.
;;       Mark before enqueue so cycles and repeated edges visit a vertex once.
;;       The adjacency and all its lists remain unchanged.
;;
;;       # Examples
;;
;;       ```scheme
;;       (let (selected (vector #t #f))
;;         (gerbil-ascent-graph-close! '#((1) ()) selected)
;;         selected)
;;       ;; => #(#t #t)
;;       ```
;;     %
(def (gerbil-ascent-graph-close! successors selected)
  (let ((count (vector-length selected)) (pending []))
    (let seed ((index 0))
      (when (< index count)
        (when (vector-ref selected index) (set! pending (cons index pending)))
        (seed (+ index 1))))
    (def (enqueue target)
      (unless (vector-ref selected target)
        (vector-set! selected target #t)
        (set! pending (cons target pending))))
    (let visit ()
      (match pending
        ([] (void))
        ([source . rest]
         (set! pending rest)
         (for-each enqueue (vector-ref successors source))
         (visit))))))

;; gerbil-ascent-graph-components
;;   : (-> (Vector [Nat]) [[Nat]])
;;   : (-> DenseAdjacency SourceOrderedComponents)
;;   | doc m%
;;       Partition dense vertex IDs into strongly connected components.
;;       Every inter-component edge points from an earlier to a later
;;       component. Traversal tables belong to this invocation; edge labels
;;       and validation remain with the caller. Dense vectors avoid hashing
;;       during the linear graph traversal.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-graph-components '#((1) (0 2) ()))
;;       ;; => ((0 1) (2))
;;       ```
;;     %
(def (gerbil-ascent-graph-components successors)
  (let* ((count (vector-length successors))
         (next-index 0)
         (indices (make-vector count #f))
         (lowlinks (make-vector count 0))
         (stack [])
         (components []))
    ;; A frame holds the vertex and the unvisited suffix of its adjacency
    ;; list. It belongs to this invocation; caller-owned edges stay immutable.
    (def (enter node frames)
      (let (index next-index)
        (set! next-index (fx+ next-index 1))
        (vector-set! indices node index)
        (vector-set! lowlinks node index)
        (set! stack (cons node stack)))
      (make-graph-frame node (vector-ref successors node) frames))
    ;; indices doubles as DFS state: #f is unseen, a fixnum is on the SCC
    ;; stack, and #t is completed. A completed vertex has no discovery index.
    (def (lower! node index)
      (vector-set! lowlinks node (fxmin (vector-ref lowlinks node) index)))
    (def (finish node)
      (when (fx= (vector-ref lowlinks node) (vector-ref indices node))
        (let pop ((members []))
          (with ([member . rest] stack)
            (set! stack rest)
            (vector-set! indices member #t)
            (let (collected (cons member members))
              (if (fx= member node)
                (set! components (cons collected components))
                (pop collected)))))))
    ;; Each transition returns the next frame. The private record replaces
    ;; the positional pair-of-pairs and owns only its remaining edge suffix.
    (def (advance node remaining (frame :- graph-frame))
      (with ([neighbor . rest] remaining)
        (set! frame.remaining rest)
        (let (index (vector-ref indices neighbor))
          (cond
           ((not index) (enter neighbor frame))
           ((eq? index #t) frame)
           (else (lower! node index) frame)))))
    (def (leave node parent)
      (finish node)
      (when parent
        (using (parent :- graph-frame)
          (lower! parent.node (vector-ref lowlinks node))))
      parent)
    (def (traverse root)
      (let walk ((frame (enter root #f)))
        (when frame
          ;; Every frame is constructed by enter; no caller value enters here.
          (using (frame :- graph-frame)
            (walk (if (pair? frame.remaining)
                    (advance frame.node frame.remaining frame)
                    (leave frame.node frame.parent)))))))
    (let roots ((root 0))
      (when (fx< root count)
        (unless (vector-ref indices root) (traverse root))
        (roots (fx+ root 1))))
    components))
