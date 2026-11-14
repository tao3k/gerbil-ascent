;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Research kernels for closed, static, dense, unit-weight relation snapshots.
(import (only-in :clan/poo/object .o .ref .call)
        (only-in :clan/poo/trie UIntTrieSet))
(export row-frontier-prototype row-warshall-prototype)

;; Walk bounded fixnum chunks, avoiding one bignum subtraction per set node.
(def (mask-visit mask visit)
  (let chunks ((remaining mask) (offset 0))
    (unless (zero? remaining)
      (let bits ((word (bitwise-and remaining 65535)))
        (unless (fxzero? word)
          (let (bit (fx- (integer-length word) 1))
            (visit (fx+ offset bit))
            (bits (fx- word (fxarithmetic-shift-left 1 bit))))))
      (chunks (arithmetic-shift remaining -16) (fx+ offset 16)))))

(def (source-rows pairs radix)
  (unless (and (exact-integer? radix) (<= 2 radix 512))
    (error "research row kernel requires radix 2..512" radix))
  (let (rows (make-vector radix 0))
    (.call UIntTrieSet .foldl
           (lambda (pair _)
             (let ((from (quotient pair radix)) (to (modulo pair radix)))
               (when (>= from radix)
                 (error "Ascent table pair exceeds the declared radix" pair))
               (vector-set! rows from
                            (bitwise-ior (vector-ref rows from) (arithmetic-shift 1 to)))))
           (void) pairs)
    rows))

(def (row-pairs rows radix)
  (let (pairs [])
    (let sources ((from (- radix 1)))
      (when (>= from 0)
        (let* ((mask (vector-ref rows from)) (base (* from radix)))
          (let chunks ((block (quotient (- (integer-length mask) 1) 16)))
            (when (and (not (zero? mask)) (>= block 0))
              (let bits ((word (bitwise-and (arithmetic-shift mask (- (* block 16))) 65535)))
                (unless (fxzero? word)
                  (let (bit (fx- (integer-length word) 1))
                    (set! pairs (cons (+ base (* block 16) bit) pairs))
                    (bits (fx- word (fxarithmetic-shift-left 1 bit))))))
              (chunks (- block 1)))))
        (sources (- from 1))))
    pairs))

(def (row-contains rows radix pair)
  (and (exact-integer? pair) (<= 0 pair) (< pair (* radix radix))
       (bit-set? (modulo pair radix) (vector-ref rows (quotient pair radix)))))

(def (publish rows radix)
  (.o (pairs (row-pairs rows radix))
      (contains? (lambda (pair) (row-contains rows radix pair)))))

(def (expand-mask mask adjacency)
  (let (expanded 0)
    (mask-visit mask
      (lambda (via) (set! expanded (bitwise-ior expanded (vector-ref adjacency via)))))
    expanded))

(def (compose-rows left right include-source?)
  (let* ((radix (vector-length right)) (rows (make-vector radix 0)))
    (let sources ((from 0))
      (when (< from radix)
        (let* ((mask (vector-ref left from)) (joined (expand-mask mask right)))
          (vector-set! rows from (if include-source? (bitwise-ior mask joined) joined)))
        (sources (+ from 1))))
    rows))

;; A vertex is initially seen only if connected by a real length-one edge.
;; Unlike reflexive BFS, the source may be discovered later through a cycle.
(def (frontier-paths adjacency max-pairs distances?)
  (when (and max-pairs (not (and (exact-integer? max-pairs) (>= max-pairs 0))))
    (error "invalid ASCENT closure pair budget" max-pairs))
  (let* ((radix (vector-length adjacency)) (reachable (make-vector radix 0))
         (distance-rows (and distances? (make-vector radix #f))) (count 0))
    (def (admit-mask! mask)
      (set! count (+ count (bit-count mask)))
      (when (and max-pairs (> count max-pairs))
        (error "ASCENT derived pair budget exceeded" max-pairs)))
    ;; Seed the whole source relation before admitting any derived pair.
    (let seeds ((from 0))
      (when (< from radix)
        (admit-mask! (vector-ref adjacency from))
        (seeds (+ from 1))))
    (let sources ((from 0))
      (when (< from radix)
        (let* ((seed (vector-ref adjacency from))
               (distances (and distances? (not (zero? seed)) (make-u16vector radix 0))))
          (when distances (vector-set! distance-rows from distances))
          (let levels ((frontier seed) (seen seed) (depth 1))
            (when distances
              (mask-visit frontier (lambda (to) (u16vector-set! distances to depth))))
            (if (zero? frontier)
              (vector-set! reachable from seen)
              (let (next (bitwise-and (expand-mask frontier adjacency) (bitwise-not seen)))
                (admit-mask! next)
                (levels next (bitwise-ior seen next) (+ depth 1)))))
          (sources (+ from 1)))))
    (vector reachable distance-rows)))

;; Boolean Warshall row unions; closure only, without shortest distances.
(def (warshall-rows adjacency)
  (let* ((radix (vector-length adjacency)) (rows (vector-copy adjacency)))
    (let pivots ((via 0))
      (when (< via radix)
        (let ((right (vector-ref rows via)))
          (let sources ((from 0))
            (when (< from radix)
              (when (bit-set? via (vector-ref rows from))
                (vector-set! rows from (bitwise-ior (vector-ref rows from) right)))
              (sources (+ from 1)))))
        (pivots (+ via 1))))
    rows))

(def (prototype warshall?)
  (.o (:: self [] source-pairs radix)
      (row-source (source-rows source-pairs radix))
      (path-analysis (frontier-paths (.ref self 'row-source) #f #t))
      (closure-projection
       (publish (if warshall? (warshall-rows (.ref self 'row-source))
                    (vector-ref (.ref self 'path-analysis) 0)) radix))
      (closure-pairs (.ref (.ref self 'closure-projection) 'pairs))
      (closure-contains? (.ref (.ref self 'closure-projection) 'contains?))
      (closure-bounded
       (lambda (budget) (publish (vector-ref (frontier-paths (.ref self 'row-source) budget #f) 0) radix)))
      (shortest-distance-projection
       (let* ((analysis (.ref self 'path-analysis)) (distances (vector-ref analysis 1)))
         (.o (pairs (row-pairs (vector-ref analysis 0) radix))
             (distance-of
              (lambda (pair)
                (and (exact-integer? pair) (<= 0 pair) (< pair (* radix radix))
                     (let (row (vector-ref distances (quotient pair radix)))
                       (and row
                            (let (value (u16vector-ref row (modulo pair radix)))
                              (and (> value 0) value))))))))))
      (shortest-distance-pairs (.ref (.ref self 'shortest-distance-projection) 'pairs))
      (shortest-distance-of (.ref (.ref self 'shortest-distance-projection) 'distance-of))
      (at-most-two-hop-projection (publish (compose-rows (.ref self 'row-source) (.ref self 'row-source) #t) radix))
      (at-most-two-hop-pairs (.ref (.ref self 'at-most-two-hop-projection) 'pairs))
      (at-most-two-hop-contains? (.ref (.ref self 'at-most-two-hop-projection) 'contains?))
      (two-hop-pairs (row-pairs (compose-rows (.ref self 'row-source) (.ref self 'row-source) #f) radix))
      (compose-left (lambda (left) (row-pairs (compose-rows (source-rows left radix) (.ref self 'row-source) #f) radix)))))

(def row-frontier-prototype (prototype #f))
(def row-warshall-prototype (prototype #t))
