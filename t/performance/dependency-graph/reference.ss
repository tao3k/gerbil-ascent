;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Tarjan over dense vertex IDs. Components are returned in source-before-
;;; target order; callers retain ownership of their edge labels and metadata.
;;; Numeric specialization boundary: IDs and discovery indices are bounded
;;; by vector-length, including the final count sentinel. Checked fx operations
;;; apply only to these dense traversal counters, never to caller edge labels.
(export gerbil-ascent-graph-components gerbil-ascent-graph-close!)

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
    (let visit ()
      (unless (null? pending)
        (let (source (car pending))
          (set! pending (cdr pending))
          (for-each
           (lambda (target)
             (unless (vector-ref selected target)
               (vector-set! selected target #t)
               (set! pending (cons target pending))))
           (vector-ref successors source)))
        (visit)))))

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
         (on-stack (make-vector count #f))
         (stack [])
         (components []))
    ;; A frame holds the vertex and the unvisited suffix of its adjacency
    ;; list. It belongs to this invocation; caller-owned edges stay immutable.
    (def (enter node frames)
      (let (index next-index)
        (set! next-index (fx+ next-index 1))
        (vector-set! indices node index)
        (vector-set! lowlinks node index)
        (vector-set! on-stack node #t)
        (set! stack (cons node stack)))
      (cons (cons node (vector-ref successors node)) frames))
    (def (finish node)
      (when (fx= (vector-ref lowlinks node) (vector-ref indices node))
        (let pop ((members []))
          (let (member (car stack))
            (set! stack (cdr stack))
            (vector-set! on-stack member #f)
            (let (collected (cons member members))
              (if (fx= member node)
                (set! components (cons collected components))
                (pop collected)))))))
    ;; DFS returns through explicit frames instead of a Scheme continuation
    ;; per vertex. Updating the parent happens only after its child finishes,
    ;; just as in recursive Tarjan; cross edges use the discovery index.
    (let roots ((root 0))
      (when (fx< root count)
        (unless (vector-ref indices root)
          (let walk ((frames (enter root [])))
            (unless (null? frames)
              (let (frame (car frames))
                (with ([node . remaining] frame)
                  (if (pair? remaining)
                    (let (neighbor (car remaining))
                      (set-cdr! frame (cdr remaining))
                      (cond
                       ((not (vector-ref indices neighbor))
                        (walk (enter neighbor frames)))
                       (else
                        (when (vector-ref on-stack neighbor)
                          (vector-set! lowlinks node
                            (fxmin (vector-ref lowlinks node)
                                 (vector-ref indices neighbor))))
                        (walk frames))))
                    (let (parents (cdr frames))
                      (finish node)
                      (unless (null? parents)
                        (let (parent (caar parents))
                          (vector-set! lowlinks parent
                            (fxmin (vector-ref lowlinks parent)
                                 (vector-ref lowlinks node)))))
                      (walk parents))))))))
        (roots (fx+ root 1))))
    components))
