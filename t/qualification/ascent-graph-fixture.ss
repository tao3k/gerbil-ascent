;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Frozen recursive Tarjan from 761dcea. The reference retains its original
;;; traversal and ordering for direct native comparisons.
(export ascent-reference-graph-components)

;; ascent-reference-graph-components
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
;;       (ascent-reference-graph-components '#((1) (0 2) ()))
;;       ;; => ((0 1) (2))
;;       ```
;;     %
(def (ascent-reference-graph-components successors)
  (let* ((count (vector-length successors))
         (next-index 0)
         (indices (make-vector count #f))
         (lowlinks (make-vector count 0))
         (on-stack (make-vector count #f))
         (stack [])
         (components []))
    (def (visit node)
      (let (index next-index)
        (set! next-index (+ next-index 1))
        (vector-set! indices node index)
        (vector-set! lowlinks node index)
        (vector-set! on-stack node #t)
        (set! stack (cons node stack)))
      (vector-set! lowlinks node
        (foldl
         (lambda (neighbor lowlink)
           (cond
            ((not (vector-ref indices neighbor))
             (visit neighbor)
             (min lowlink (vector-ref lowlinks neighbor)))
            ((vector-ref on-stack neighbor)
             (min lowlink (vector-ref indices neighbor)))
            (else lowlink)))
         (vector-ref lowlinks node)
         (vector-ref successors node)))
      (when (= (vector-ref lowlinks node) (vector-ref indices node))
        (let pop ((members []))
          (let (member (car stack))
            (set! stack (cdr stack))
            (vector-set! on-stack member #f)
            (let (collected (cons member members))
              (if (= member node)
                (set! components (cons collected components))
                (pop collected)))))))
    (for-each (lambda (node)
                (unless (vector-ref indices node) (visit node)))
              (iota count))
    components))
