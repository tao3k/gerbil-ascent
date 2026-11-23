;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Tarjan over dense vertex IDs. Components are returned in source-before-
;;; target order; callers retain ownership of their edge labels and metadata.
;;; Numeric specialization boundary: IDs and discovery indices are bounded
;;; by vector-length, including the final count sentinel. Checked fx operations
;;; apply only to these dense traversal counters, never to caller edge labels.
(import (only-in "scc-state.ss" gerbil-ascent-scc-state))
(export gerbil-ascent-graph-components gerbil-ascent-graph-components/checkpoint
        gerbil-ascent-graph-components/borrowed gerbil-ascent-graph-components/packed
        gerbil-ascent-graph-components/packed-boundary
        gerbil-ascent-graph-close!)

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
  (gerbil-ascent-graph-components/checkpoint successors #f))

(def (gerbil-ascent-graph-components/checkpoint successors checkpoint!)
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
          (gerbil-ascent-scc-state index (known)
            (enter neighbor frame)
            frame
            (begin (lower! node known) frame)))))
    (def (leave node parent)
      (finish node)
      (when parent
        (using (parent :- graph-frame)
          (lower! parent.node (vector-ref lowlinks node))))
      parent)
    (def (traverse root)
      (let walk ((frame (enter root #f)))
        (when frame
          (when checkpoint! (checkpoint!))
          ;; Every frame is constructed by enter; no caller value enters here.
          (using (frame :- graph-frame)
            (walk (if (pair? frame.remaining)
                    (advance frame.node frame.remaining frame)
                    (leave frame.node frame.parent)))))))
    (let roots ((root 0))
      (when (fx< root count)
        (when checkpoint! (checkpoint!))
        (unless (vector-ref indices root) (traverse root))
        (roots (fx+ root 1))))
    components))

;; The low-word and follower transitions are adapted from POO's
;; compact-discover. Specialize the cursor operations at expansion:
;; a list cursor owns a suffix, and a packed cursor owns an offset.
;; Restricted roots mark all outside vertices retired in either form.
(defrule (borrowed-components successors checkpoint! selected
                              make-resume save! load
                              start bound more? target advance observe!)
  (let* ((count (vector-length successors))
         (infinity (+ (* 2 count) 1))
         (lows (make-u32vector count (if selected infinity 0)))
         (links (make-u32vector count 0))
         (resume (make-resume count))
         (clock 0) (followers 0) (components []))
    (unless (and (fixnum? infinity) (<= infinity #xffffffff))
      (error "ASCENT SCC discovery extent" count))
    (def (enter! node parent)
      (set! clock (fx+ clock 2))
      (u32vector-set! lows node clock)
      (u32vector-set! links node parent)
      clock)
    (def (retire! leader low)
      (let pop ((members []))
        (let (member (fx- followers 1))
          (if (and (not (fx= followers 0))
                   (fx>= (u32vector-ref lows member) low))
            (begin
              (checkpoint!)
              (set! followers (u32vector-ref links member))
              (u32vector-set! lows member infinity)
              (pop (cons member members)))
            (begin
              (u32vector-set! lows leader infinity)
              (set! components (cons (cons leader members) components)))))))
    (def (visit node low)
      (let (row (vector-ref successors node))
        (walk node row (start row) (bound row) low)))
    (def (walk node row cursor end low)
      (checkpoint!)
      (if (more? cursor end)
        (let* ((next (target row cursor))
               (other (u32vector-ref lows next))
               (after (advance cursor)))
          (if (fx= other 0)
            (begin
              (save! resume node after)
              (u32vector-set! lows node low)
              (let (entered (enter! next (fx+ node 1)))
                (visit next entered)))
            (begin
              (observe! node next (fx= other infinity))
              (walk node row after end (if (fx< other low) (fxior other 1) low)))))
        ;; Read the active parent before installing a follower link.
        (let ((parent (u32vector-ref links node)) (leader? (fx= (fxand low 1) 0)))
          (if leader?
            (retire! node low)
            (begin
              (u32vector-set! lows node low)
              (u32vector-set! links node followers)
              (set! followers (fx+ node 1))))
          (unless (fx= parent 0)
            (let* ((p (fx- parent 1)) (prior (u32vector-ref lows p))
                   (parent-row (vector-ref successors p)))
              (observe! p node leader?)
              (walk p parent-row (load resume p) (bound parent-row)
                (if (and (not leader?) (fx< low prior)) (fxior low 1) prior)))))))
    (def (visit-root! root)
      (checkpoint!)
      (when (fx= (u32vector-ref lows root) 0)
        (visit root (enter! root 0))
        (unless (fx= followers 0)
          (error "ASCENT SCC did not retire all followers" root))))
    (if selected
      (begin
        (for-each (lambda (v) (checkpoint!) (u32vector-set! lows v 0)) selected)
        (for-each visit-root! selected))
      (let roots ((root 0))
        (when (fx< root count)
          (visit-root! root)
          (roots (fx+ root 1)))))
    components))

(def (gerbil-ascent-graph-components/borrowed successors checkpoint! (selected #f))
  (defrule (start row) row)
  (defrule (bound row) #f)
  (defrule (more? cursor end) (pair? cursor))
  (defrule (target row cursor) (car cursor))
  (borrowed-components successors checkpoint! selected
    make-vector vector-set! vector-ref start bound more? target cdr ignore-boundary!))

(defrule (ignore-boundary! source target retired?) (void))

(def (gerbil-ascent-graph-components/packed successors checkpoint! (selected #f))
  (defrule (start row) 0)
  (defrule (advance cursor) (fx+ cursor 1))
  (borrowed-components successors checkpoint! selected
    make-u32vector u32vector-set! u32vector-ref
    start u16vector-length fx< u16vector-ref advance ignore-boundary!))

;; Capture an exact subset of raw arrows. The complementary observations
;; only need their ordinal envelope in the selected extent. A packed
;; list avoids a full-domain vector of mostly empty capture rows.
(def (gerbil-ascent-graph-components/packed-boundary successors checkpoint! selected)
  (let* ((count (vector-length successors)) (overflow (fx+ count 1))
         (first count) (last 0))
    (for-each (lambda (v)
                (checkpoint!)
                (when (fx< v first) (set! first v))
                (when (fx> v last) (set! last v))) selected)
    (let* ((span (max 0 (fx+ (fx- last first) 1)))
           (minimum (make-u16vector span count)) (maximum (make-u16vector span 0))
           (arcs []) (recorded 0))
      (defrule (start row) 0)
      (defrule (advance cursor) (fx+ cursor 1))
      (defrule (observe! source target retired?)
        (let* ((v source) (w target) (at (fx- v first)) (lo (u16vector-ref minimum at)))
          (when (fx<= lo count)
            (if retired?
              (if (fx< recorded count)
                (begin
                  (set! recorded (fx+ recorded 1))
                  (set! arcs (cons (fx+ (fx* v count) w) arcs)))
                (u16vector-set! minimum at overflow))
              (begin
                (when (fx< w lo) (u16vector-set! minimum at w))
                (when (fx> w (u16vector-ref maximum at))
                  (u16vector-set! maximum at w)))))))
      (let (parts (borrowed-components successors checkpoint! selected
                    make-u32vector u32vector-set! u32vector-ref
                    start u16vector-length fx< u16vector-ref advance observe!))
        (values parts (vector first minimum maximum arcs))))))
