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
        (only-in :clan/poo/trie SimpleTrie UIntTrieSet))

(export ascent-table-expression-baseline ascent-table-expression-point-reference
        ascent-table-expression-global-point-reference)

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

;; Only private scalar rows are grouped. The public constructors still admit
;; every complete neighbor set and the complete persistent index on publication.
(def (baseline-index pairs radix)
  (let ((groups (make-hash-table)) (rows []))
    (.call UIntTrieSet .foldl
      (lambda (pair unused)
        (let (source (quotient pair radix))
          (hash-put! groups source
            (cons (modulo pair radix) (hash-ref groups source [])))) #f)
      #f pairs)
    (hash-for-each
      (lambda (source targets)
        (set! rows (cons (cons source (.call UIntTrieSet .<-list targets)) rows)))
      groups)
    (.call AdjacencyTable .<-list rows)))

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

(def (baseline-compose pairs index radix)
  (.call UIntTrieSet .<-list
    (.call UIntTrieSet .foldl
      (lambda (pair joined)
        (let* ((source (quotient pair radix))
               (middle (modulo pair radix))
               (destinations (.call AdjacencyTable .ref index middle
                 (lambda () (.ref UIntTrieSet '.empty)))))
          (.call UIntTrieSet .foldl
            (lambda (target output) (cons (+ (* source radix) target) output))
            joined destinations))) [] pairs)))

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
  (let* ((index (baseline-index pairs radix))
         (two-hop (baseline-compose pairs index radix)))
    (.call UIntTrieSet .list<-
      (.call UIntTrieSet .<-list
        (append (.call UIntTrieSet .list<- pairs) (.call UIntTrieSet .list<- two-hop))))))
