;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Binary relation kernels over encoded finite pairs and private adjacency.
;;; Canonical projections expose read-only queries; retained state belongs to
;;; the caller that demands a view or invokes a bounded closure.

(import (only-in :clan/poo/object .o .ref .call)
        (only-in "ordered-pair-set.ss" gerbil-ascent-ordered-pair-set)
        (only-in :clan/poo/trie UIntTrieSet)
        (only-in :std/iter for in-range)
        (only-in :clan/poo/support/base until))

(export gerbil-ascent-relation-closure-bounded
        relation-view
        native-relation-view?
        relation-source-visitor
        relation-compose
        relation-delta-step
        relation-closure
        relation-projection
        relation-shortest-distance-projection
        (struct-out native-path-distances)
        native-sparse-distance-analysis
        build-native-path-layout
        compute-native-path-analysis
        path-projection
        path-distance-projection)

;; A provenance marker for the private prepared view, not a global result cache.
(def native-path-view-tag (list 'native-path-view))

;; : (-> EncodedRows DistanceQuery NativePathDistances)
(defstruct native-path-distances (pairs distance) final: #t)

;; native-relation-view?
;; : (forall (a) (-> a Boolean))
;; : (-> UntrustedRelationView Boolean)
;; | doc m%
;;     Recognize the provenance marker of this module's private prepared views.
;;     Custom source/neighbor visitor packets cannot authorize shared analysis.
;;
;;     # Examples
;;
;;     ```scheme
;;     (native-relation-view? (relation-view source 513))
;;     ;; => #t
;;     ```
;;   %
(def (native-relation-view? view)
  (and (vector? view) (= (vector-length view) 4)
       (eq? (vector-ref view 3) native-path-view-tag)))

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

;; relation-view
;;   : (-> UIntTrieSet Radix IndexedSource)
;;   | doc m%
;;       Prepare private adjacency and source visitors for a finite encoded relation. The radix must exceed one; pairs outside its domain are rejected. Each call owns its adjacency; callers retain only query procedures and the provenance-bearing view.
;;
;;       # Examples
;;
;;       ```scheme
;;       (relation-view (.call UIntTrieSet .<-list [10 19]) 8)
;;       ;; => a prepared view of edges 1->2 and 2->3
;;       ```
;;     %
(def (relation-view pairs radix)
  (unless (and (exact-integer? radix) (> radix 1))
    (error "Ascent table radix must be an integer greater than one" radix))
  (if (> radix 512)
    (sparse-relation-view pairs radix)
    (let (index (make-vector radix []))
      (.call UIntTrieSet .foldl
        (lambda (pair _)
          (let ((source (quotient pair radix)) (target (modulo pair radix)))
            (when (>= source radix)
              (error "Ascent table pair exceeds the declared radix" pair))
            (vector-set! index source (cons target (vector-ref index source)))))
        (void) pairs)
      ;; Ordered trie admission reverses each target list. Source traversal
      ;; restores encoded key order; direct neighbor visitation keeps its order.
      ;; Radix <= 512 proves source, target and encoded base fit fixnums.
      (vector
        (lambda (consume)
          (let visit ((source 0))
            (when (fx< source radix)
              (visit-source-row (vector-ref index source) (fx* source radix) consume)
              (visit (fx+ source 1)))))
        (lambda (source) (vector-ref index source))
        (lambda (source consume) (for-each consume (vector-ref index source)))
        native-path-view-tag))))

;; sparse-relation-view
;; : (forall (a) (-> a Radix IndexedSource))
;; : (-> UIntTrieSet Radix IndexedSource)
;; | doc m%
;;     Own adjacency only for admitted source identities. Exact radix and pair
;;     arithmetic stay external; source traversal uses the ordered native trie.
;;     Targets retain the same reverse admission order as the dense view.
;;
;;     # Examples
;;
;;     ```scheme
;;     (sparse-relation-view (.call UIntTrieSet .<-list [515 1029]) 513)
;;     ;; => a private view of edges 1->2 and 2->3
;;     ```
;;   %
(def (sparse-relation-view pairs radix)
  (let (index (make-hash-table))
    (.call UIntTrieSet .foldl
      (lambda (pair _)
        (let ((source (quotient pair radix)) (target (modulo pair radix)))
          (when (>= source radix)
            (error "Ascent table pair exceeds the declared radix" pair))
          (hash-put! index source (cons target (or (hash-get index source) [])))))
      (void) pairs)
    (def (targets source)
      (unless (and (exact-integer? source) (<= 0 source) (< source radix))
        (error "Ascent table source exceeds the declared radix" source))
      (or (hash-get index source) []))
    (vector (relation-source-visitor pairs) targets
      (lambda (source consume) (for-each consume (targets source)))
      native-path-view-tag)))

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

;; : (-> [UInt] UInt DistanceRow Nat [UInt] (-> UInt Void) [UInt])
(def (distance-row-targets targets base row depth next discover!)
  (if (null? targets) next
    (let* ((target (car targets)) (previous (vector-ref row target)))
      (if (and previous (<= previous depth))
        (distance-row-targets (cdr targets) base row depth next discover!)
        (let (pair (+ base target))
          (unless previous (discover! pair))
          (vector-set! row target depth)
          (distance-row-targets (cdr targets) base row depth (cons pair next) discover!))))))

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
          (gerbil-ascent-ordered-pair-set
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
(def (gerbil-ascent-relation-closure-bounded source radix max-pairs)
  (let* ((view (relation-view source radix))
         (layout (and (<= 32 radix 128)
                      (build-native-path-layout view (vector-ref view 2) radix))))
    (if layout
      (path-projection (vector-ref (compute-native-path-analysis layout max-pairs #f) 0) radix)
      (relation-closure (vector-ref view 0) (vector-ref view 2) radix max-pairs (vector-ref view 1)))))

;;; The selected unit-weight Ascent path lattice: Dual<usize> joins competing
;;; paths by minimum distance. The frontier contains only newly discovered or
;;; improved pairs, and private storage is published through read-only slots.
;; : (forall (a) (-> SourceVisitor (-> UInt (-> UInt Void) a) UInt (Maybe NeighborRows) DistanceProjection))
;; : (-> SourceVisitor NeighborVisitor Radix (Maybe NeighborRows) DistanceProjection)
(def (relation-shortest-distance-projection visit-source neighbors-of radix native-neighbors)
  (let* ((dense? (<= radix 512))
         ;; Allocate a distance row only after this origin reaches a pair.
         ;; Boxed depths preserve the general callback path without introducing
         ;; a new numeric bound; sparse domains retain their hash storage.
         (distances (and dense? (make-vector radix #f)))
         ;; Distance storage already decides membership. Small outputs retain
         ;; their list instead of allocating a second domain-sized container.
         (bitmap-threshold (and dense? (max 16 (quotient (* radix radix) 64))))
         (bits #f)
         (discovered-count 0)
         (sparse (and (not dense?) (make-hash-table)))
         (frontier [])
         (discovered []))
    (def (lookup-distance pair)
      (if dense?
        (let (row (vector-ref distances (quotient pair radix)))
          (and row (vector-ref row (modulo pair radix))))
        (hash-get sparse pair)))
    (def (discover! pair)
      (if bits
        (pair-bitmap-admit! bits pair)
        (begin
          (set! discovered (cons pair discovered))
          (set! discovered-count (+ discovered-count 1))
          (when (and dense? (= discovered-count bitmap-threshold))
            (set! bits (pair-bitmap radix))
            (for-each (lambda (known) (pair-bitmap-admit! bits known)) discovered)
            (set! discovered [])))))
    (def (improve! pair depth)
      (let* ((from (and dense? (quotient pair radix)))
             (to (and dense? (modulo pair radix)))
             (row (and dense? (vector-ref distances from)))
             (previous (if dense? (and row (vector-ref row to)) (hash-get sparse pair))))
        (if (and previous (<= previous depth))
          #f
          (begin
            (unless previous (discover! pair))
            (if dense?
              (let (present (or row (let (new (make-vector radix #f))
                                     (vector-set! distances from new)
                                     new)))
                (vector-set! present to depth))
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
           (let* ((from (quotient pair radix))
                 (via (modulo pair radix))
                 (depth (if dense?
                          (vector-ref (vector-ref distances from) via)
                          (lookup-distance pair))))
             (if native-neighbors
               (if dense?
                 ;; Every frontier origin already owns a seeded row. Native
                 ;; targets are finite, so row addressing needs no pair decode.
                 (set! next (distance-row-targets (native-neighbors via) (* from radix)
                                                 (vector-ref distances from) (+ depth 1) next discover!))
                 (set! next (distance-targets (native-neighbors via) (* from radix) (+ depth 1) next improve!)))
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

;; native-sparse-distance-analysis
;; : (forall (p) (-> (IndexedSource p) Radix (NativePathDistances p)))
;; : (-> NativeRelationView Radix NativePathDistances)
;; | doc m%
;;     Prepare occupied node offsets and traverse one private vector frontier per
;;     source. External pair identities stay exact; nonempty cycles keep their
;;     shortest positive distance. Only a canonical view authorizes this path.
;;
;;     # Examples
;;
;;     ```scheme
;;     (native-sparse-distance-analysis (relation-view source 513) 513)
;;     ;; => a private record of complete pairs and an exact distance query
;;     ```
;;   %
(def (native-sparse-distance-analysis view radix)
  (unless (and (native-relation-view? view) (exact-integer? radix) (> radix 512))
    (error "Ascent sparse path analysis requires a canonical sparse view"))
  (with (#(visit-source targets _ _) view)
    (let (offsets (make-hash-table))
      (visit-source (lambda (pair)
        (hash-put! offsets (quotient pair radix) #t)
        (hash-put! offsets (modulo pair radix) #t)))
      (let* ((nodes (list->vector (list-sort < (hash-keys offsets))))
             (count (vector-length nodes))
             (adjacency (make-vector count []))
             (visited (make-vector count 0))
             (distances (make-hash-table))
             (ordered []))
        ;; Admission ended. Reuse the membership owner for local physical offsets.
        (for (slot (in-range count))
          (hash-put! offsets (vector-ref nodes slot) slot))
        (for (slot (in-range count))
          (vector-set! adjacency slot
            (map (lambda (node) (hash-get offsets node)) (targets (vector-ref nodes slot)))))
        (for (origin (in-range count))
          (let (seed (vector-ref adjacency origin))
            (when (pair? seed)
              (let ((stamp (+ origin 1))
                    (base (* (vector-ref nodes origin) radix))
                    (depth 1) (next []))
                ;; This invocation alone owns visitation. Source stamps reuse
                ;; one physical vector; discovery/expansion closures are bound
                ;; once per origin rather than allocated at every path probe.
                (def (discover! target)
                  (unless (= (vector-ref visited target) stamp)
                    (vector-set! visited target stamp)
                    (let (pair (+ base (vector-ref nodes target)))
                      (hash-put! distances pair depth)
                      (set! ordered (cons pair ordered)))
                    (set! next (cons target next))))
                (def (expand! middle)
                  (for-each discover! (vector-ref adjacency middle)))
                (for-each discover! seed)
                (let visit ((frontier next))
                  (unless (null? frontier)
                    (set! depth (+ depth 1))
                    (set! next [])
                    (for-each expand! frontier)
                    (visit next)))))))
        (make-native-path-distances (list-sort < ordered)
          (lambda (pair)
            (and (exact-integer? pair) (<= 0 pair) (< pair (* radix radix))
                 (hash-get distances pair))))))))

;;; Whole-row path propagation is confined to canonical, dense snapshots.
;;; The general pair frontier remains authoritative for callbacks and sparse
;;; graphs. Selection and analysis are both owned by the demanded expression.
;; build-native-path-layout
;;   : (-> IndexedSource NeighborVisitor Radix (Maybe PathRows))
;;   | doc m%
;;       Build private bit rows only for dense canonical views with radix 32 through 128. A replaced neighbor callback or insufficient density returns false, preserving the general visitor path.
;;
;;       # Examples
;;
;;       ```scheme
;;       (build-native-path-layout view overridden-neighbors 64)
;;       ;; => #f when the callback differs from the view's canonical visitor
;;       ```
;;     %
(def (build-native-path-layout view neighbors radix)
  (and (<= 32 radix 128)
       (= (vector-length view) 4)
       (eq? (vector-ref view 3) native-path-view-tag)
       (eq? neighbors (vector-ref view 2))
       (let ((targets (vector-ref view 1)) (minimum (quotient (+ (* radix 3) 3) 4)))
         ;; Reject low-degree graphs before allocating a second representation.
         (and (let check ((from 0))
                (or (= from radix)
                    (and (>= (length (targets from)) minimum) (check (+ from 1)))))
              (let (rows (make-vector radix 0))
                (let sources ((from 0))
                  (when (< from radix)
                    (let bits ((rest (targets from)) (mask 0))
                      (if (null? rest)
                        (vector-set! rows from mask)
                        (bits (cdr rest) (bitwise-ior mask (arithmetic-shift 1 (car rest))))))
                    (sources (+ from 1))))
                rows)))))

;; : (-> UIntMask PathRows UIntMask UIntMask)
(def (path-expand mask adjacency full)
  (let (expanded 0)
    (let chunks ((remaining mask) (offset 0))
      (unless (or (zero? remaining) (= expanded full))
        (let bits ((word (bitwise-and remaining 65535)))
          (unless (or (fxzero? word) (= expanded full))
            (let (bit (fx- (integer-length word) 1))
              (set! expanded (bitwise-ior expanded (vector-ref adjacency (fx+ offset bit))))
              (bits (fx- word (fxarithmetic-shift-left 1 bit))))))
        (chunks (arithmetic-shift remaining -16) (fx+ offset 16))))
    expanded))

;; : (-> UIntMask DistanceRow Nat Void)
(def (path-label! mask distances depth)
  (let chunks ((remaining mask) (offset 0))
    (unless (zero? remaining)
      (let bits ((word (bitwise-and remaining 65535)))
        (unless (fxzero? word)
          (let (bit (fx- (integer-length word) 1))
            (vector-set! distances (fx+ offset bit) depth)
            (bits (fx- word (fxarithmetic-shift-left 1 bit))))))
      (chunks (arithmetic-shift remaining -16) (fx+ offset 16)))))

;; compute-native-path-analysis
;;   : (-> PathRows (Maybe UInt) Boolean PathAnalysis)
;;   | doc m%
;;       Compute positive closure and optional shortest distances into fresh private rows. Count source and derived pairs against the optional budget; failure leaves the input adjacency unchanged.
;;
;;       # Examples
;;
;;       ```scheme
;;       (compute-native-path-analysis (vector 2 4 0) 3 #f)
;;       ;; => #(#(6 4 0) #f), encoding 0->1, 0->2 and 1->2
;;       ```
;;     %
(def (compute-native-path-analysis adjacency max-pairs distances?)
  (when (and max-pairs (not (and (exact-integer? max-pairs) (>= max-pairs 0))))
    (error "invalid ASCENT closure pair budget" max-pairs))
  (let* ((radix (vector-length adjacency)) (full (- (arithmetic-shift 1 radix) 1))
         (rows (make-vector radix 0))
         (distances (and distances? (make-vector radix #f))) (count 0))
    (def (admit! mask)
      (set! count (+ count (bit-count mask)))
      (when (and max-pairs (> count max-pairs))
        (error "ASCENT derived pair budget exceeded" max-pairs)))
    ;; Count all actual source edges before admitting derived pairs.
    (let seed ((from 0))
      (when (< from radix)
        (admit! (vector-ref adjacency from))
        (seed (+ from 1))))
    (let sources ((from 0))
      (when (< from radix)
        (let* ((seed (vector-ref adjacency from))
               (distance (and distances? (not (zero? seed)) (make-vector radix #f))))
          (when distance (vector-set! distances from distance))
          ;; Positive paths start at outgoing edges, never a reflexive identity.
          (let levels ((frontier seed) (seen seed) (depth 1))
            (when distance (path-label! frontier distance depth))
            ;; Fully covered origins cannot discover another positive pair.
            (if (or (zero? frontier) (= seen full))
              (vector-set! rows from seen)
              (let (next (bitwise-and (path-expand frontier adjacency full) (bitwise-not seen)))
                (admit! next)
                (levels next (bitwise-ior seen next) (+ depth 1)))))
          (sources (+ from 1)))))
    (vector rows distances)))

;; : (-> PathRows Radix EncodedRows)
(def (path-pairs rows radix)
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

;; : (-> PathRows Radix PairProjection)
(def (path-projection rows radix)
  (.o (pairs (path-pairs rows radix))
      (contains? (lambda (pair)
                   (and (exact-integer? pair) (<= 0 pair) (< pair (* radix radix))
                        (bit-set? (modulo pair radix) (vector-ref rows (quotient pair radix))))))))

;; : (-> PathAnalysis Radix DistanceProjection)
(def (path-distance-projection analysis radix)
  (let (distances (vector-ref analysis 1))
    ;; Publish separately from closure: mutable public lists must not alias.
    (.o (pairs (path-pairs (vector-ref analysis 0) radix))
        (distance-of (lambda (pair)
                       (and (exact-integer? pair) (<= 0 pair) (< pair (* radix radix))
                            (let (row (vector-ref distances (quotient pair radix)))
                              (and row (vector-ref row (modulo pair radix))))))))))
