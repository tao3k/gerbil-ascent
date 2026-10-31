;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Bounded binary-relation expression. The input is an official persistent
;;; UIntTrieSet snapshot; the indexed join uses local Scheme containers and
;;; publishes a canonical, distinct list of encoded pairs.

(import (only-in :clan/poo/object .o .ref .call)
        (only-in :clan/poo/trie UIntTrieSet)
        (only-in :clan/poo/support/base until))

(export distance-rows-reference-prototype
        distance-rows-reference-closure-bounded)

;; : (-> DenseTargets DenseBase (-> UInt Void) Void)
(def (visit-source-row targets base consume)
  (unless (null? targets)
    (visit-source-row (cdr targets) base consume)
    (consume (fx+ base (car targets)))))

;;; Dense relations store sixteen pair admissions per word. Only occupied
;;; words are retained for publication: sorting those word indices and walking
;;; their set bits yields canonical rows without sorting or copying every pair.
;;; The bounded words fit fixnums on both 32-bit and 64-bit Gambit runtimes.
;; : (-> Radix DensePairBitmap)
(def (pair-bitmap radix)
  (let (limit (* radix radix))
    (vector (make-u16vector (quotient (+ limit 15) 16) 0) [] limit)))

;; : (-> DensePairBitmap UInt Boolean)
(def (pair-bitmap-contains? bitmap pair)
  (let ((word (fxarithmetic-shift-right pair 4))
        (mask (fxarithmetic-shift-left 1 (fxand pair 15))))
    (not (fxzero? (fxand (u16vector-ref (vector-ref bitmap 0) word) mask)))))

;; : (-> DensePairBitmap UInt Boolean)
(def (pair-bitmap-admit! bitmap pair)
  ;; Keep padding in the final word outside the declared finite relation.
  (unless (and (fixnum? pair) (fx<= 0 pair) (fx< pair (vector-ref bitmap 2)))
    (error "Ascent table pair exceeds the declared radix" pair))
  (let* ((words (vector-ref bitmap 0))
         (word (fxarithmetic-shift-right pair 4))
         (mask (fxarithmetic-shift-left 1 (fxand pair 15)))
         (previous (u16vector-ref words word)))
    (if (fxzero? (fxand previous mask))
      (begin
        (when (fxzero? previous)
          (vector-set! bitmap 1 (cons word (vector-ref bitmap 1))))
        (u16vector-set! words word (fxior previous mask))
        #t)
      #f)))

;; : (-> DensePairBitmap EncodedRows)
(def (pair-bitmap-rows bitmap)
  (let ((words (vector-ref bitmap 0)) (rows []))
    (for-each
     (lambda (word)
       (let loop ((remaining (u16vector-ref words word)))
         (unless (fxzero? remaining)
           (let* ((bit (fx- (integer-length remaining) 1))
                  (mask (fxarithmetic-shift-left 1 bit)))
             (set! rows (cons (fx+ (fxarithmetic-shift-left word 4) bit) rows))
             (loop (fx- remaining mask))))))
     (list-sort > (vector-ref bitmap 1)))
    rows))

;; : (-> UIntTrieSet Radix IndexedSource)
(def (relation-view pairs radix)
  (unless (and (exact-integer? radix) (> radix 1))
    (error "Ascent table radix must be an integer greater than one" radix))
  (let (index (make-vector radix []))
    (.call UIntTrieSet .foldl
           (lambda (pair _)
             (let ((source (quotient pair radix)) (target (modulo pair radix)))
               (when (>= source radix)
                 (error "Ascent table pair exceeds the declared radix" pair))
               (vector-set! index source (cons target (vector-ref index source)))))
           (void) pairs)
    ;; The official fold is ordered by encoded key. Reverse each private
    ;; neighbor list by traversal, without copying or publishing the vector.
    (vector
     (if (<= radix 512)
       ;; Radix <= 512 proves source, target and encoded base fit fixnums.
       ;; Keep generic arithmetic and the native fold for unbounded sparse keys.
       (lambda (consume)
         (let visit ((source 0))
           (when (fx< source radix)
             (visit-source-row (vector-ref index source) (fx* source radix) consume)
             (visit (fx+ source 1)))))
       ;; Sparse domains retain the native fold: no scan proportional to an
       ;; arbitrarily large radix, and no unbounded reverse-row recursion.
       (relation-source-visitor pairs))
     (lambda (source) (vector-ref index source))
     (lambda (source consume) (for-each consume (vector-ref index source))))))

;; : (-> UIntTrieSet SourceVisitor)
(def (relation-source-visitor pairs)
  (lambda (consume)
    (.call UIntTrieSet .foldl (lambda (pair _) (consume pair)) (void) pairs)))

;; : (-> [UInt] UInt (-> UInt Void) Void)
(def (project-targets! targets base add-pair!)
  (unless (null? targets)
    (add-pair! (+ base (car targets)))
    (project-targets! (cdr targets) base add-pair!)))

;; : (-> [UInt] UInt [UInt] (-> UInt Boolean) [UInt])
(def (closure-targets targets base next add-pair!)
  (if (null? targets) next
    (let (pair (+ base (car targets)))
      (closure-targets (cdr targets) base
                      (if (add-pair! pair) (cons pair next) next) add-pair!))))

;; : (-> [UInt] UInt Nat [UInt] (-> UInt Nat Boolean) [UInt])
(def (distance-targets targets base depth next improve!)
  (if (null? targets) next
    (let (pair (+ base (car targets)))
      (distance-targets (cdr targets) base depth
                       (if (improve! pair depth) (cons pair next) next) improve!))))

;; : (forall (a) (-> SourceVisitor (-> UInt (-> UInt Void) a) UInt Boolean (Maybe NeighborRows) PairProjection))
;; : (-> SourceVisitor NeighborVisitor Radix Boolean (Maybe NeighborRows) PairProjection)
(def (relation-projection visit-source neighbors-of radix include-source? native-neighbors)
  (let* ((dense? (<= radix 512))
         (bits (and dense? (pair-bitmap radix)))
         (sparse (and (not dense?) (make-hash-table)))
         (unique []))
    (def (add-pair! pair)
      (if dense?
        (pair-bitmap-admit! bits pair)
        (unless (hash-get sparse pair)
          (hash-put! sparse pair #t)
          (set! unique (cons pair unique)))))
    (visit-source
           (lambda (pair)
             (let ((source (quotient pair radix))
                   (middle (modulo pair radix)))
               (when (>= source radix)
                 (error "Ascent table pair exceeds the declared radix" pair))
               (when include-source? (add-pair! pair))
               (if native-neighbors
                 (project-targets! (native-neighbors middle) (* source radix) add-pair!)
                 (neighbors-of middle
                   (lambda (target) (add-pair! (+ (* source radix) target))))))))
    (.o (contains?
         (lambda (pair)
           (and (exact-integer? pair) (<= 0 pair) (< pair (* radix radix))
                (if dense? (pair-bitmap-contains? bits pair)
                    (hash-get sparse pair)))))
        (pairs (if dense? (pair-bitmap-rows bits) (list-sort < unique))))))

;; : (forall (a) (-> SourceVisitor (-> UInt (-> UInt Void) a) UInt Boolean (Maybe NeighborRows) EncodedRows))
;; : (-> SourceVisitor NeighborVisitor Radix Boolean (Maybe NeighborRows) EncodedRows)
(def (relation-compose visit-source neighbors-of radix include-source? native-neighbors)
  (.ref (relation-projection visit-source neighbors-of radix include-source? native-neighbors) 'pairs))

;;; Compose one frontier and retain only pairs absent from the accumulated
;;; relation. The caller owns repetition, bounds, and completion.
;; : (-> SourceVisitor UIntTrieSet NeighborVisitor Radix (Maybe NeighborRows) DeltaProjection)
(def (relation-delta-step visit-frontier accumulated neighbors-of radix native-neighbors)
  (let* ((candidates
          (.call UIntTrieSet .<-list
                 (relation-compose visit-frontier neighbors-of radix #f native-neighbors)))
         ;; V19 Set .diff omits operands in its Table .merge forwarding.
         (delta
          (.call (.ref UIntTrieSet 'Table) .merge
                 (lambda (_ left right) (and (not right) left))
                 candidates accumulated))
         (combined (.call UIntTrieSet .union accumulated delta)))
    (.o (new-pairs delta) (all-pairs combined))))

;;; The finite-domain transitive closure for this binary relation, using the
;;; library's until combinator and set operations. This is a specific rule
;;; evaluation, not a second generic prototype fixed-point implementation.
;; : (forall (a) (-> SourceVisitor (-> UInt (-> UInt Void) a) UInt (Maybe Nat) (Maybe NeighborRows) PairProjection))
;; : (-> SourceVisitor NeighborVisitor Radix (Maybe Nat) (Maybe NeighborRows) PairProjection)
(def (relation-closure visit-source neighbors-of radix max-pairs native-neighbors)
  (when (and max-pairs
             (not (and (exact-integer? max-pairs) (>= max-pairs 0))))
    (error "invalid ASCENT closure pair budget" max-pairs))
  (let* ((dense? (<= radix 512))
         (bits (and dense? (pair-bitmap radix)))
         (sparse (and (not dense?) (make-hash-table)))
         (frontier [])
         (all [])
         (count 0))
    (def (add-pair! pair)
      (if dense?
        (if (pair-bitmap-admit! bits pair)
          (begin
            (when (and max-pairs (>= count max-pairs))
              (error "ASCENT derived pair budget exceeded" max-pairs))
            (set! count (+ count 1))
            #t)
          #f)
        (if (hash-get sparse pair)
          #f
          (begin
            (when (and max-pairs (>= count max-pairs))
              (error "ASCENT derived pair budget exceeded" max-pairs))
            (hash-put! sparse pair #t)
            (set! count (+ count 1))
            (set! all (cons pair all))
            #t))))
    (visit-source
           (lambda (pair)
             (when (add-pair! pair)
               (set! frontier (cons pair frontier)))))
    (until (null? frontier)
      (let (next [])
        (for-each
         (lambda (pair)
           (let ((origin (quotient pair radix))
                 (middle (modulo pair radix)))
             (if native-neighbors
               (set! next (closure-targets (native-neighbors middle) (* origin radix) next add-pair!))
               (neighbors-of middle
                 (lambda (target)
                   (let (candidate (+ (* origin radix) target))
                     (when (add-pair! candidate)
                       (set! next (cons candidate next)))))))))
         frontier)
        (set! frontier next)))
    (.o (pairs (if dense? (pair-bitmap-rows bits) (list-sort < all)))
        (contains?
         (lambda (pair)
           (and (exact-integer? pair) (<= 0 pair) (< pair (* radix radix))
                (if dense? (pair-bitmap-contains? bits pair)
                    (hash-get sparse pair))))))))

;; : (-> UIntTrieSet Radix Nat PairProjection)
(def (distance-rows-reference-closure-bounded source radix max-pairs)
  (let (view (relation-view source radix))
    (relation-closure (vector-ref view 0) (vector-ref view 2) radix max-pairs (vector-ref view 1))))

;;; The selected unit-weight Ascent path lattice: Dual<usize> joins competing
;;; paths by minimum distance. The frontier contains only newly discovered or
;;; improved pairs, and private storage is published through read-only slots.
;; : (forall (a) (-> SourceVisitor (-> UInt (-> UInt Void) a) UInt (Maybe NeighborRows) DistanceProjection))
;; : (-> SourceVisitor NeighborVisitor Radix (Maybe NeighborRows) DistanceProjection)
(def (relation-shortest-distance-projection visit-source neighbors-of radix native-neighbors)
  (let* ((dense? (<= radix 512))
         (distances (and dense? (make-vector (* radix radix) #f)))
         ;; Distance storage already decides membership. Small outputs retain
         ;; their list instead of allocating a second domain-sized container.
         (bitmap-threshold (and dense? (max 16 (quotient (* radix radix) 64))))
         (bits #f)
         (discovered-count 0)
         (sparse (and (not dense?) (make-hash-table)))
         (frontier [])
         (discovered []))
    (def (lookup-distance pair)
      (if dense? (vector-ref distances pair) (hash-get sparse pair)))
    (def (improve! pair depth)
      (let (previous (lookup-distance pair))
        (if (and previous (<= previous depth))
          #f
          (begin
            (unless previous
              (if bits
                (pair-bitmap-admit! bits pair)
                (begin
                  (set! discovered (cons pair discovered))
                  (set! discovered-count (+ discovered-count 1))
                  (when (and dense? (= discovered-count bitmap-threshold))
                    (set! bits (pair-bitmap radix))
                    (for-each (lambda (known) (pair-bitmap-admit! bits known)) discovered)
                    (set! discovered [])))))
            (if dense? (vector-set! distances pair depth)
                (hash-put! sparse pair depth))
            #t))))
    (visit-source
           (lambda (pair)
             (when (improve! pair 1)
               (set! frontier (cons pair frontier)))))
    (until (null? frontier)
      (let (next [])
        (for-each
         (lambda (pair)
           (let ((from (quotient pair radix))
                 (via (modulo pair radix))
                 (depth (lookup-distance pair)))
             (if native-neighbors
               (set! next (distance-targets (native-neighbors via) (* from radix) (+ depth 1) next improve!))
               (neighbors-of via
                 (lambda (to)
                   (let (candidate (+ (* from radix) to))
                     (when (improve! candidate (+ depth 1))
                       (set! next (cons candidate next)))))))))
         frontier)
        (set! frontier next)))
    (.o (pairs (if bits (pair-bitmap-rows bits) (list-sort < discovered)))
        (distance-of
         (lambda (pair)
           (and (exact-integer? pair) (<= 0 pair) (< pair (* radix radix))
                (lookup-distance pair)))))))

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
(def distance-rows-reference-prototype
  (.o (:: self [] source-pairs radix)
      (indexed-source (relation-view source-pairs radix))
      (right-index (vector-ref (.ref self 'indexed-source) 2))
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
       (with-relation-view self
         (lambda (visit-source neighbors native-neighbors)
           (relation-closure visit-source neighbors radix #f native-neighbors))))
      (closure-bounded
       (lambda (max-pairs)
         (with-relation-view self
           (lambda (visit-source neighbors native-neighbors)
             (relation-closure visit-source neighbors radix max-pairs native-neighbors)))))
      (closure-pairs (.ref (.ref self 'closure-projection) 'pairs))
      (closure-contains? (.ref (.ref self 'closure-projection) 'contains?))
      (closure-set (.call UIntTrieSet .<-list (.ref self 'closure-pairs)))
      (shortest-distance-projection
       (with-relation-view self
         (lambda (visit-source neighbors native-neighbors)
           (relation-shortest-distance-projection visit-source neighbors radix native-neighbors))))
      (shortest-distance-pairs (.ref (.ref self 'shortest-distance-projection) 'pairs))
      (shortest-distance-of (.ref (.ref self 'shortest-distance-projection) 'distance-of))
      (two-hop-pairs ((.ref self 'compose-left) source-pairs))
      (at-most-two-hop-projection
       (with-relation-view self
         (lambda (visit-source neighbors native-neighbors)
           (relation-projection visit-source neighbors radix #t native-neighbors))))
      (at-most-two-hop-contains? (.ref (.ref self 'at-most-two-hop-projection) 'contains?))
      (at-most-two-hop-pairs (.ref (.ref self 'at-most-two-hop-projection) 'pairs))))
