;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Persistent-trie control based on POO PR #34, 4ee113d3.
;;; Build the private sort-merge stream, canonicalize its keys, and reuse the
;;; ordered Patricia builder. Public projection admits the complete carrier.
;;; Point joins use source-local sets; the original global point algorithm
;;; remains a separate diagnostic witness.
;;; Benchmark evidence only; this is not a second runtime path.

(import (only-in :clan/poo/object .ref .call)
        (only-in :clan/poo/number UInt)
        (only-in :clan/poo/trie SimpleTrie UIntTrieSet)
        (only-in :std/list/list delete-duplicates/hash)
        (only-in :gerbil-ascent/core/ordered-pair-set gerbil-ascent-ordered-pair-set))

(export ascent-table-expression-baseline ascent-table-expression-point-reference
        ascent-table-expression-global-point-reference
        baseline-indexes baseline-compose baseline-ordered-keys)

(def AdjacencyTable (SimpleTrie UInt UIntTrieSet))
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

;; Capture scalar input through the public set fold. The join consumes each
;; adjacency only as a sorted stream, so it needs no persistent index roots.
(def (baseline-indexes pairs radix)
  (let ((outgoing (make-hash-table)) (incoming (make-hash-table)) (source-rows []))
    (.call UIntTrieSet .foldl
      (lambda (pair unused)
        (let ((source (quotient pair radix)) (target (modulo pair radix)))
          (hash-put! outgoing source (cons target (hash-ref outgoing source [])))
          (hash-put! incoming target (cons source (hash-ref incoming target [])))
          (set! source-rows (cons pair source-rows))) #f)
      #f pairs)
    (def (ordered groups)
      (list-sort (lambda (left right) (< (car left) (car right)))
                 (hash->list groups)))
    (values (ordered outgoing) (ordered incoming) source-rows)))

(def (baseline-compose/point pairs index radix)
  ;; Admit the complete trie once and project each immutable neighbor set
  ;; once. The global output still uses the original public point insertion.
  (let (neighbors
        (list->hash-table
          (map (lambda (entry)
                 (cons (car entry) (.call UIntTrieSet .list<- (cdr entry))))
               (.call AdjacencyTable .list<- index))))
    (.call UIntTrieSet .foldl
      (lambda (pair joined)
        (let ((source (quotient pair radix))
              (middle (modulo pair radix)))
          (foldl (lambda (target output)
                   (.call UIntTrieSet .cons (+ (* source radix) target) output))
                 joined (hash-ref neighbors middle []))))
      (.ref UIntTrieSet '.empty) pairs)))

(def (baseline-compose incoming outgoing radix)
  ;; The join stream is private: admit the complete combined set once in the
  ;; caller instead of constructing, projecting and readmitting a temporary set.
  (let loop ((left incoming) (right outgoing) (rows []))
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

;; Both streams are private. The sort reuses the duplicate filter's fresh
;; result spine, so non-unique join paths never create intermediate trie roots.
(def (baseline-ordered-keys source-rows two-hop)
  (list-sort! < (delete-duplicates/hash (append! source-rows two-hop))))

(def (ascent-table-expression-baseline pairs radix)
  (let-values (((outgoing incoming source-rows) (baseline-indexes pairs radix)))
    (let* ((two-hop (baseline-compose incoming outgoing radix))
           (keys (baseline-ordered-keys source-rows two-hop)))
      (.call UIntTrieSet .list<- (gerbil-ascent-ordered-pair-set keys)))))
