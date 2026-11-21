;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/iter for in-range)
        (only-in :gerbil-ascent/core/dependency-graph gerbil-ascent-graph-components/packed)
        (only-in :gerbil-ascent/core/view-value make-relation-view make-part-visitors))
(export gerbil-ascent-condense-closure gerbil-ascent-extend-condensed-closure
        gerbil-ascent-remove-condensed-edge
        condensed-closure? condensed-closure-source condensed-closure-size
        gerbil-ascent-condensed-same-partition?
        gerbil-ascent-condensed-closure-view gerbil-ascent-condensed-witness
        gerbil-ascent-verify-condensed-witness condensed-witness-vertices)

;; Construction owns the ordinal map and adjacency, and publishes only after
;; every source row is admitted. A delta copies only the changing vectors.
(defstruct condensed-closure (source size positions labels adjacent members owner direct reach order) final: #t)
(defstruct condensed-order (labels runs count) final: #t)
(defstruct condensed-run (group start stop) final: #t)

;; This route bounds the dense bit sets by the number of admitted endpoints.
;; Wider graphs and unsupported inputs use the general positive evaluator.
(def dense-limit 8192)

(defrule (slot-bit i) (arithmetic-shift 1 i))
(def (fold-members bits consume state)
  (let loop ((remaining bits) (acc state))
    (if (zero? remaining) acc
      (let* ((other (bitwise-and remaining (- remaining 1)))
             (i (- (integer-length (bitwise-xor other remaining)) 1)))
        (loop other (consume i acc))))))

(def (build-condensed-order ordered positions owner checkpoint!)
  ;; Run boundaries share the immutable ordered label spine.
  (let scan ((rest ordered) (start ordered) (group #f) (runs []) (count 0))
    (checkpoint!)
    (if (null? rest)
      (if group
        (make-condensed-order ordered (reverse! (cons (make-condensed-run group start rest) runs))
          (+ count 1))
        (make-condensed-order ordered [] 0))
      (let (next (vector-ref owner (hash-get positions (car rest))))
        (cond ((not group) (scan (cdr rest) rest next runs count))
              ((= next group) (scan (cdr rest) start group runs count))
              (else (scan (cdr rest) rest next
                      (cons (make-condensed-run group start rest) runs) (+ count 1))))))))

(def (visit-condensed-runs (order :- condensed-order) mask consume)
  (for-each
    (lambda ((run :- condensed-run))
      (when (bit-set? run.group mask)
        (let walk ((rest run.start))
          (unless (eq? rest run.stop)
            (consume (car rest))
            (walk (cdr rest))))))
    order.runs))

(defrule (for-neighbor (target row) body ...)
  (let* ((edges row) (end (u16vector-length edges)))
    (let loop ((i 0))
      (unless (fx= i end)
        (let (target (u16vector-ref edges i)) body ...)
        (loop (fx+ i 1))))))

;; A cold capture checks the complete source once. Its validation table
;; and temporary encoded arcs are released before component traversal.
(def (capture-adjacency size visit-source checkpoint!)
  (let/cc decline
    (unless (and (exact-integer? size) (<= 0 size (* dense-limit dense-limit)))
      (decline #f))
    (let ((positions (make-hash-table-eqv)) (pairs (make-hash-table-eqv))
          (degrees (make-u16vector dense-limit 0))
          (vertices []) (edges (make-u32vector size))
          (width 0) (count 0))
      (def (position! key)
        (unless (fixnum? key) (decline #f))
        (or (hash-get positions key)
            (let (i width)
              (when (= i dense-limit) (decline #f))
              (hash-put! positions key i)
              (set! vertices (cons key vertices))
              (set! width (+ width 1))
              i)))
      (visit-source
       (lambda (left right)
         (checkpoint!)
         (when (= count size) (decline #f))
         (let* ((from (position! left)) (to (position! right))
                (pair (+ (* dense-limit from) to)))
           (when (hash-get pairs pair) (decline #f))
           (hash-put! pairs pair #t)
           (u32vector-set! edges count pair)
           (u16vector-set! degrees from (fx+ (u16vector-ref degrees from) 1))
           (set! count (+ count 1)))))
      (unless (= count size) (decline #f))
      (let (adjacent (make-vector width))
        (for (v (in-range width))
          (checkpoint!)
          (vector-set! adjacent v (make-u16vector (u16vector-ref degrees v)))
          (u16vector-set! degrees v 0))
        ;; The second pass visits our encoded arcs, in original source order.
        (let fill ((i 0))
          (unless (fx= i count)
            (checkpoint!)
            (let* ((pair (u32vector-ref edges i))
                   (from (fxquotient pair dense-limit)) (to (fxremainder pair dense-limit))
                   (offset (u16vector-ref degrees from)))
              (u16vector-set! (vector-ref adjacent from) offset to)
              (u16vector-set! degrees from (fx+ offset 1)))
            (fill (fx+ i 1))))
        (vector positions (list->vector (reverse! vertices)) adjacent)))))

(def (gerbil-ascent-condense-closure source size visit-source checkpoint!)
  (alet (capture (capture-adjacency size visit-source checkpoint!))
    (condense-adjacent source size (vector-ref capture 0) (vector-ref capture 1)
      (vector-ref capture 2) #f gerbil-ascent-graph-components/packed checkpoint!)))

;; Consume the admitted adjacency directly. The partitioner returns each
;; component before its quotient successors.
(def (condense-adjacent source size positions labels adjacent ordered partition checkpoint!)
  (let* ((members (list->vector (partition adjacent checkpoint!)))
         (groups (vector-length members))
         (owner (make-vector (vector-length adjacent) #f))
         (direct (make-vector groups 0))
         (single? (= groups 1))
         (cyclic? (and single? (> size 0))))
    ;; A nonempty graph with one SCC has just the self bit.
    (when cyclic? (vector-set! direct 0 1))
    (for (g (in-range groups))
      (let (vertices (vector-ref members g))
        ;; Each nontrivial SCC already witnesses a nonempty internal path.
        (when (and (not single?) (pair? (cdr vertices)))
          (vector-set! direct g (slot-bit g))
          (set! cyclic? #t))
        (for-each (lambda (v) (checkpoint!) (vector-set! owner v g)) vertices)))
    (unless single?
      (for (v (in-range (vector-length adjacent)))
        (let* ((g (vector-ref owner v))
               (nontrivial? (pair? (cdr (vector-ref members g)))))
          (let* ((row (vector-ref adjacent v)) (end (u16vector-length row)))
            (let walk ((offset 0) (mask (vector-ref direct g)))
              (if (fx= offset end)
                (vector-set! direct g mask)
                (begin
                  (checkpoint!)
                  (let* ((h (vector-ref owner (u16vector-ref row offset)))
                         (next
                          (cond ((fx= g h)
                                 (if nontrivial? mask
                                   (begin
                                     (set! cyclic? #t)
                                     (bitwise-ior (slot-bit g) mask))))
                                ((bit-set? h mask) mask)
                                (else (bitwise-ior (slot-bit h) mask)))))
                    (walk (fx+ offset 1) next)))))))))
    (and cyclic?
         (let (reach (vector-copy direct))
           (let close ((g (- groups 1)))
             (when (>= g 0)
               (checkpoint!)
               (let (mask (vector-ref direct g))
                 (vector-set! reach g
                   (fold-members mask
                     (lambda (h out)
                       (checkpoint!)
                       (bitwise-ior out (vector-ref reach h)))
                     mask)))
               (close (- g 1))))
           (make-condensed-closure source size positions labels
             adjacent members owner direct reach
             (build-condensed-order (or ordered (list-sort < (vector->list labels)))
               positions owner checkpoint!))))))

(def (repair-partition (prior :- condensed-closure) source size adjacent checkpoint!)
  (condense-adjacent source size prior.positions prior.labels adjacent
    (condensed-order-labels prior.order)
    gerbil-ascent-graph-components/packed checkpoint!))

;; Local partitions may assign dense ordinals in a different order.
;; Traverse the quotient dependencies before closing each mask.
(def (close-edited-quotient direct checkpoint!)
  (let* ((groups (vector-length direct))
         (reach (make-vector groups 0))
         (status (make-vector groups #f)))
    (def (close! g)
      (checkpoint!)
      (case (vector-ref status g)
        ((done) (vector-ref reach g))
        ((active) (error "ASCENT edited quotient has a cycle"))
        (else
         (vector-set! status g 'active)
         (let* ((mask (vector-ref direct g))
                (closed
                 (fold-members mask
                   (lambda (h out)
                     (checkpoint!)
                     (if (= g h) out (bitwise-ior out (close! h)))) mask)))
           (vector-set! reach g closed)
           (vector-set! status g 'done)
           closed))))
    (for (g (in-range groups)) (close! g))
    reach))

;; Keep the member spines for unchanged SCCs. Translate their old mask
;; bits; only a destination that split needs concrete target endpoints.
(def (repair-local (prior :- condensed-closure) source size adjacent affected replacements split? checkpoint!)
  (let* ((old-groups (vector-length prior.members))
         (translate (make-vector old-groups #f))
         (unchanged
          (foldl (lambda (g out)
                   (checkpoint!)
                   (if (bit-set? g affected) out (cons g out)))
                 [] (iota old-groups)))
         (old-order (reverse! unchanged))
         (fresh-at (length old-order))
         (members (list->vector
                   (append (map (lambda (g) (vector-ref prior.members g)) old-order)
                           replacements)))
         (groups (vector-length members))
         (owner (make-vector (vector-length adjacent) #f))
         (direct (make-vector groups 0)))
    (for-each (lambda (old g) (vector-set! translate old g)) old-order (iota fresh-at))
    (unless split?
      (fold-members affected (lambda (old _) (vector-set! translate old fresh-at)) #f))
    (for (g (in-range groups))
      (for-each (lambda (v) (checkpoint!) (vector-set! owner v g)) (vector-ref members g)))
    (def (remap old bits)
      (fold-members (vector-ref prior.direct old)
        (lambda (h out)
          (checkpoint!)
          (let (next (vector-ref translate h))
            (if next (bitwise-ior out (slot-bit next)) out))) bits))
    (def (scan members mask target?)
      (for-each
       (lambda (v)
         (checkpoint!)
         (for-neighbor (w (vector-ref adjacent v))
           (checkpoint!)
           (when (target? w)
             (let (h (vector-ref owner w))
               (unless (bit-set? h mask) (set! mask (bitwise-ior mask (slot-bit h))))))))
       members)
      mask)
    (for-each
     (lambda (old g)
       (let (mask (remap old 0))
         (vector-set! direct g
           (if (and split? (not (zero? (bitwise-and affected (vector-ref prior.direct old)))))
             (scan (vector-ref prior.members old) mask
               (lambda (w) (bit-set? (vector-ref prior.owner w) affected)))
             mask))))
     old-order (iota fresh-at))
    (if split?
      (for (g (in-range fresh-at groups))
        (vector-set! direct g (scan (vector-ref members g) 0 (lambda (_) #t))))
      ;; The newly added edge is internal. It supplies a self bit even
      ;; when none of the merged groups previously had a self bit.
      (vector-set! direct fresh-at (fold-members affected remap (slot-bit fresh-at))))
    (let (reach (close-edited-quotient direct checkpoint!))
      (make-condensed-closure source size prior.positions prior.labels
        adjacent members owner direct reach
        (build-condensed-order (condensed-order-labels prior.order)
          prior.positions owner checkpoint!)))))

(def (merge-local (prior :- condensed-closure) source size adjacent a b checkpoint!)
  (let* ((forward (bitwise-ior (slot-bit b) (vector-ref prior.reach b)))
         (affected
          (fold-members forward
            (lambda (g out)
              (checkpoint!)
              (if (or (= g a) (bit-set? a (vector-ref prior.reach g)))
                (bitwise-ior out (slot-bit g)) out)) 0))
         (vertices
          (fold-members affected
            (lambda (g out)
              (foldl (lambda (v tail) (checkpoint!) (cons v tail)) out (vector-ref prior.members g)))
            [])))
    (repair-local prior source size adjacent affected (list vertices) #f checkpoint!)))

(def (split-local (prior :- condensed-closure) source size adjacent group checkpoint!)
  (let (parts (gerbil-ascent-graph-components/packed adjacent checkpoint!
                (vector-ref prior.members group)))
    (if (null? (cdr parts))
      (make-condensed-closure source size prior.positions prior.labels
        adjacent prior.members prior.owner prior.direct prior.reach prior.order)
      (repair-local prior source size adjacent (slot-bit group) parts #t checkpoint!))))

(def (gerbil-ascent-condensed-same-partition? (prior :- condensed-closure)
                                             (next :- condensed-closure))
  (eq? prior.owner next.owner))

(def (neighbor-offset row target (checkpoint! #f))
  (and target
       (let (end (u16vector-length row))
         (let scan ((i 0))
           (and (fx< i end)
                (begin
                  (when checkpoint! (checkpoint!))
                  (if (fx= (u16vector-ref row i) target) i (scan (fx+ i 1)))))))))

(def (splice-neighbor row at skip replacement)
  (let* ((added (if replacement 1 0))
         (next (make-u16vector (+ (- (u16vector-length row) skip) added))))
    (u16vector-copy! next 0 row 0 at)
    (when replacement (u16vector-set! next at replacement))
    (u16vector-copy! next (+ at added) row (+ at skip))
    next))

;; Appends share the exact previous source spine. A packed replacement
;; instead supplies the next target of this origin to preserve witness order.
;; An edge that can merge components must rebuild the quotient.
(def (gerbil-ascent-extend-condensed-closure (prior :- condensed-closure) source size row checkpoint!
                                           (packed-edit? #f) (local? #f))
  (let* ((left (car row)) (right (cadr row))
         (x (and (fixnum? left) (hash-get prior.positions left)))
         (y (and (fixnum? right) (hash-get prior.positions right))))
    (and x y (not (neighbor-offset (vector-ref prior.adjacent x) y))
         (let* ((a (vector-ref prior.owner x)) (b (vector-ref prior.owner y))
                (adjacent (vector-copy prior.adjacent)) (edges (vector-ref adjacent x)))
           (let (offset
                 (if packed-edit?
                   (let (next (caddr row))
                     (or (neighbor-offset edges (and next (hash-get prior.positions next)) checkpoint!)
                         (u16vector-length edges)))
                   0))
             (vector-set! adjacent x (splice-neighbor edges offset 0 y)))
           (if (and (not (= a b)) (bit-set? a (vector-ref prior.reach b)))
             (if local?
               (merge-local prior source size adjacent a b checkpoint!)
               (repair-partition prior source size adjacent checkpoint!))
             (let* ((direct (vector-copy prior.direct)) (reach (vector-copy prior.reach))
                    (suffix (bitwise-ior (slot-bit b) (vector-ref reach b))))
               (vector-set! direct a (bitwise-ior (slot-bit b) (vector-ref direct a)))
               (for (g (in-range (vector-length reach)))
                 (checkpoint!)
                 (when (or (= g a) (bit-set? a (vector-ref prior.reach g)))
                   (vector-set! reach g (bitwise-ior (vector-ref prior.reach g) suffix))))
               (make-condensed-closure source size prior.positions prior.labels
                 adjacent prior.members prior.owner direct reach prior.order)))))))

(def (has-cross-edge? adjacent members owner a b checkpoint!)
  (let/cc found
    (for-each
      (lambda (v)
        (for-neighbor (target (vector-ref adjacent v))
          (checkpoint!)
          (when (= (vector-ref owner target) b) (found #t))))
      (vector-ref members a))
    #f))

(def (withdrawal-reach direct prior-reach origin checkpoint!)
  (let ((reach (vector-copy prior-reach))
        (ready (make-vector (vector-length direct) #f)))
    (def (affected? g)
      (or (= g origin) (bit-set? origin (vector-ref prior-reach g))))
    (def (refresh! g)
      (checkpoint!)
      (unless (or (vector-ref ready g) (not (affected? g)))
        (let (mask (vector-ref direct g))
          (vector-set! reach g
            (fold-members mask
              (lambda (h bits)
                ;; SCC self bits represent nonempty internal paths. The
                ;; remaining edges form a DAG, in any ordinal order.
                (unless (= g h) (refresh! h))
                (if (= g h) bits (bitwise-ior bits (vector-ref reach h))))
              mask))
          (vector-set! ready g #t))))
    (for (g (in-range (vector-length reach))) (refresh! g))
    reach))

;; A non-self edge inside a component may split it, but both endpoints
;; remain incident. A cross-edge edit retains both cyclic owner domains.
(def (gerbil-ascent-remove-condensed-edge (prior :- condensed-closure) source size row checkpoint!
                                           (local? #f))
  (let ((x (hash-get prior.positions (car row))) (y (hash-get prior.positions (cadr row))))
    (and x y
         (alet (at (neighbor-offset (vector-ref prior.adjacent x) y checkpoint!))
           (let ((a (vector-ref prior.owner x)) (b (vector-ref prior.owner y)))
             (cond
              ((and (= a b) (not (= x y)))
               (let (adjacent (vector-copy prior.adjacent))
                 (vector-set! adjacent x (splice-neighbor (vector-ref adjacent x) at 1 #f))
                 (if local?
                   (split-local prior source size adjacent a checkpoint!)
                   (repair-partition prior source size adjacent checkpoint!))))
              ((and local? (= x y))
               (let ((adjacent (vector-copy prior.adjacent))
                     (direct prior.direct)
                     (reach prior.reach))
                 (vector-set! adjacent x (splice-neighbor (vector-ref adjacent x) at 1 #f))
                 (when (null? (cdr (vector-ref prior.members a)))
                   (set! direct (vector-copy direct))
                   (vector-set! direct a (bitwise-and (vector-ref direct a) (bitwise-not (slot-bit a))))
                   (set! reach (withdrawal-reach direct reach a checkpoint!)))
                 (make-condensed-closure source size prior.positions prior.labels
                   adjacent prior.members prior.owner direct reach prior.order)))
              ((and (not (= a b))
                    (or local? (and (bit-set? a (vector-ref prior.direct a))
                                    (bit-set? b (vector-ref prior.direct b)))))
               (let ((adjacent (vector-copy prior.adjacent))
                     (direct prior.direct)
                     (reach prior.reach))
                 (vector-set! adjacent x (splice-neighbor (vector-ref adjacent x) at 1 #f))
                 (unless (has-cross-edge? adjacent prior.members prior.owner a b checkpoint!)
                   (set! direct (vector-copy direct))
                   (vector-set! direct a (bitwise-and (vector-ref direct a) (bitwise-not (slot-bit b))))
                   (set! reach (withdrawal-reach direct reach a checkpoint!)))
                 (make-condensed-closure source size prior.positions prior.labels
                   adjacent prior.members prior.owner direct reach prior.order)))
             (else #f)))))))

;; Group masks are exact, including the self bit only for a nonempty path.
(def (gerbil-ascent-condensed-closure-view (index :- condensed-closure) version room checkpoint!)
  (let/cc decline
    (let* ((labels index.labels) (positions index.positions) (owner index.owner)
           (members index.members) (reach index.reach) (groups (vector-length members))
           (order index.order)
           (sizes (vector-map length members)) (target-counts (make-vector groups 0)) (count 0))
      (for (g (in-range groups))
        (checkpoint!)
        (let (targets (fold-members (vector-ref reach g)
                        (lambda (h n) (checkpoint!) (+ n (vector-ref sizes h))) 0))
          (vector-set! target-counts g targets)
          (set! count (+ count (* (vector-ref sizes g) targets)))
          (when (> count room) (decline #f))))
      (let ((targets (vector-map
                       (lambda (mask)
                         (delay-atomic
                           (list-sort <
                             (fold-members mask
                               (lambda (h out)
                                 (foldl (lambda (v rest) (cons (vector-ref labels v) rest))
                                        out (vector-ref members h)))
                               []))))
                       reach)))
        (def (reachable? left right)
          (and (fixnum? left) (fixnum? right)
               (let ((x (hash-get positions left)) (y (hash-get positions right)))
                 (and x y (bit-set? (vector-ref owner y) (vector-ref reach (vector-ref owner x)))))))
        (def (contains? row)
          (and (pair? row) (pair? (cdr row)) (null? (cddr row))
               (reachable? (car row) (cadr row))))
        (def (parts columns key consume)
          (def (matches? columns key left right)
            (or (null? columns)
                (and (equal? (if (= (car columns) 0) left right) (car key))
                     (matches? (cdr columns) (cdr key) left right))))
          (def (visit left (after #f) (single-origin? #f))
            (when (fixnum? left)
              (let (ordinal (hash-get positions left))
                (when ordinal
                  (let (group (vector-ref owner ordinal))
                    (def (emit right)
                      (when (matches? columns key left right) (consume [] left right)))
                    (if (and single-origin? (<= (condensed-order-count order)
                                              (vector-ref target-counts group)))
                      (visit-condensed-runs order (vector-ref reach group) emit)
                      (let skip ((remaining (force (vector-ref targets group))))
                        (if (and after (pair? remaining) (<= (car remaining) after))
                          (skip (cdr remaining))
                          (for-each emit remaining)))))))))
          (def (scan)
            (let (origin (memv 0 columns))
              (if origin (visit (list-ref key (- (length columns) (length origin)))
                                #f (null? (cdr columns)))
                (for-each visit (condensed-order-labels order)))))
          (def (visit-pair left right order first second)
            (when (reachable? left right)
              (consume [] left right)
              ;; The callback may edit either caller-owned binding list.
              ;; In that case the old visitor would keep reading the suffix.
              (unless (and (equal? columns order)
                           (match key
                             ([a b] (and (eq? a first) (eq? b second)))
                             (else #f)))
                (visit left right)))
            (void))
          (match columns
            ([0 1] (match key
                     ([left right] (visit-pair left right '(0 1) left right))
                     (else (scan))))
            ([1 0] (match key
                     ([right left] (visit-pair left right '(1 0) right left))
                     (else (scan))))
            (else (scan))))
        (make-relation-view index.source version 0 'total count groups
          (lambda (columns key consume) (parts columns key (lambda (_ a b) (consume (list a b)))))
          contains? #f (make-part-visitors parts parts))))))

(defstruct condensed-witness (identity version path) final: #t)

(def (condensed-witness-vertices (proof :- condensed-witness))
  (map values proof.path))

;; This read-only search records one nonempty path from the captured graph.
;; It charges every inspected edge and never returns a partial witness.
(def (gerbil-ascent-condensed-witness (index :- condensed-closure) version from to budget)
  (unless (and (exact-integer? budget) (>= budget 0))
    (error "invalid ASCENT closure witness budget" budget))
  (let ((x (and (fixnum? from) (hash-get index.positions from)))
        (y (and (fixnum? to) (hash-get index.positions to))))
    (and x y (bit-set? (vector-ref index.owner y) (vector-ref index.reach (vector-ref index.owner x)))
         (let/cc finish
           (let* ((width (vector-length index.labels))
                  (parents (make-vector width #f)) (queue (make-vector width)) (after 1))
             (vector-set! parents x x)
             (vector-set! queue 0 x)
             (let search ((head 0))
               (when (< head after)
                 (let (v (vector-ref queue head))
                   (for-neighbor (next (vector-ref index.adjacent v))
                    (when (zero? budget) (finish #f))
                    (set! budget (- budget 1))
                    (when (= next y)
                      (let trace ((at v) (path (list to)))
                        (let (path (cons (vector-ref index.labels at) path))
                          (if (= at x) (finish (make-condensed-witness index.source version path))
                            (trace (vector-ref parents at) path)))))
                    (unless (vector-ref parents next)
                      (vector-set! parents next v)
                      (vector-set! queue after next)
                      (set! after (+ after 1)))))
                 (search (+ head 1))))
             #f)))))

(def (gerbil-ascent-verify-condensed-witness (index :- condensed-closure) version proof)
  (and (condensed-witness? proof)
       (eq? index.source (condensed-witness-identity proof))
       (= version (condensed-witness-version proof))
       (let (path (condensed-witness-path proof))
         (and (pair? (cdr path))
              (let check ((left (hash-get index.positions (car path))) (rest (cdr path)))
                (and left
                     (or (null? rest)
                         (let (right (hash-get index.positions (car rest)))
                           (and (neighbor-offset (vector-ref index.adjacent left) right)
                                (check right (cdr rest)))))))))))
