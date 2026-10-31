;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Persistent-trie control based on POO PR #34, 4ee113d3.
;;; Current public set insertion admits each complete root. Build the private
;;; join stream first and use the official bulk constructor once; preserve all
;;; final carrier/child checks. Point joins use source-local sets; the original
;;; global point algorithm remains a separate diagnostic witness.
;;; Benchmark evidence only; this is not a second runtime path.

(import (only-in :clan/poo/object .ref .call)
        (only-in :clan/poo/number UInt)
        (only-in :clan/poo/type List)
        (only-in :clan/poo/trie SimpleTrie UIntTrieSet))

(export ascent-table-expression-baseline ascent-table-expression-point-reference
        ascent-table-expression-global-point-reference)

(def AdjacencyTable (SimpleTrie UInt UIntTrieSet))
;; Input pairs are a set already; private neighbor lists need no second set
;; wrapper. The public index type still checks every UInt child on publication.
(def ListAdjacencyTable (SimpleTrie UInt (List UInt)))

(def (baseline-index/point pairs radix)
  (.call UIntTrieSet .foldl
         (lambda (pair index)
           (let* ((source (quotient pair radix))
                  (target (modulo pair radix))
                  (neighbors (.call AdjacencyTable .ref index source
                                    (lambda () (.ref UIntTrieSet '.empty)))))
             (.call AdjacencyTable .acons source
                    (.call UIntTrieSet .cons target neighbors)
                    index)))
         (.ref AdjacencyTable '.empty) pairs))

;; Only private scalar rows are grouped. The public constructors still admit
;; every complete neighbor list and the complete persistent index on publication.
(def (baseline-indexes pairs radix)
  (let ((outgoing (make-hash-table)) (incoming (make-hash-table)) (source-rows []))
    ;; Capture immutable scalar input once under its public fold admission.
    ;; Nothing is cached across calls; both complete indexes are still admitted.
    (.call UIntTrieSet .foldl
      (lambda (pair unused)
        (let ((source (quotient pair radix)) (target (modulo pair radix)))
          (hash-put! outgoing source (cons target (hash-ref outgoing source [])))
          (hash-put! incoming target (cons source (hash-ref incoming target [])))
          (set! source-rows (cons pair source-rows))) #f)
      #f pairs)
    (def (publish groups)
      (let (rows [])
        (hash-for-each
          (lambda (key values)
            (set! rows (cons (cons key values) rows))) groups)
        (.call ListAdjacencyTable .<-list rows)))
    (values (publish outgoing) (publish incoming) source-rows)))

(def (baseline-compose/point pairs index radix)
  (.call UIntTrieSet .foldl
         (lambda (pair joined)
           (let* ((source (quotient pair radix))
                  (middle (modulo pair radix))
                  (destinations
                   (.call AdjacencyTable .ref index middle
                          (lambda () (.ref UIntTrieSet '.empty)))))
             (.call UIntTrieSet .foldl
                    (lambda (target output)
                      (.call UIntTrieSet .cons
                             (+ (* source radix) target) output))
                    joined destinations)))
         (.ref UIntTrieSet '.empty) pairs))

(def (baseline-compose incoming outgoing radix)
  ;; Public lookup recognizes the complete table. Merge two complete public
  ;; enumerations instead of rereading that root for each of the 512 edges.
  ;; Sorting explicitly avoids depending on a backend's traversal order.
  (def (ordered table)
    (list-sort (lambda (left right) (< (car left) (car right)))
      (.call ListAdjacencyTable .list<- table)))
  ;; The join stream is private: admit the complete combined set once in the
  ;; caller instead of constructing, projecting and readmitting a temporary set.
  (let loop ((left (ordered incoming)) (right (ordered outgoing)) (rows []))
      (cond
        ((or (null? left) (null? right)) rows)
        ((< (caar left) (caar right)) (loop (cdr left) right rows))
        ((> (caar left) (caar right)) (loop left (cdr right) rows))
        (else
          (let (joined
                 (foldl
                   (lambda (source rows)
                     (foldl (lambda (target rows) (cons (+ (* source radix) target) rows))
                       rows (cdar right))) rows (cdar left)))
            (loop (cdr left) (cdr right) joined))))))

(def (ascent-table-expression-global-point-reference pairs radix)
  (let* ((index (baseline-index/point pairs radix))
         (two-hop (baseline-compose/point pairs index radix)))
    (.call UIntTrieSet .list<- (.call UIntTrieSet .union pairs two-hop))))

;; Each source owns a disjoint encoded key range. Keep every point insertion
;; and its ordinary input/result checks, but avoid recognizing unrelated source
;; ranges at each insertion. Publish the complete result through the public API.
(def (ascent-table-expression-point-reference pairs radix)
  (let* ((index (baseline-index/point pairs radix))
         (rows
          (.call AdjacencyTable .foldl
            (lambda (source neighbors rows)
              (let (local
                     (.call UIntTrieSet .foldl
                       (lambda (middle local)
                         (.call UIntTrieSet .foldl
                           (lambda (target output)
                             (.call UIntTrieSet .cons (+ (* source radix) target) output))
                           local (.call AdjacencyTable .ref index middle
                                   (lambda () (.ref UIntTrieSet '.empty)))))
                       (.ref UIntTrieSet '.empty) neighbors))
                (append (.call UIntTrieSet .list<- local) rows)))
            [] index)))
    (.call UIntTrieSet .list<-
      (.call UIntTrieSet .<-list (append (.call UIntTrieSet .list<- pairs) rows)))))

(def (ascent-table-expression-baseline pairs radix)
  (let-values (((outgoing incoming source-rows) (baseline-indexes pairs radix)))
    (let (two-hop (baseline-compose incoming outgoing radix))
      (.call UIntTrieSet .list<-
        (.call UIntTrieSet .<-list (append source-rows two-hop))))))
