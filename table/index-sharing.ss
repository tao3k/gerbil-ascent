;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Finite logical column requirements share curried physical chains. Planning
;;; owns no rows. Each engine/worker builds and extends its own physical roots.
(export gerbil-ascent-index-sharing-layout gerbil-ascent-index-sharing-certificate?
        gerbil-ascent-shared-index-build gerbil-ascent-shared-index-extend!
        gerbil-ascent-shared-index-rows)

;; gerbil-ascent-index-sharing-certificate?
;; : (forall (c) (-> (Vector [c]) (Vector (Maybe Nat)) (Vector (Maybe Nat)) Boolean))
;; : (-> AdmittedColumnSets MatchingLeft MatchingRight Boolean)
;; | doc m%
;;     Independently check matching validity and a tight endpoint cover before
;;     publishing a layout. Alternating reachability constructs the cover; all
;;     graph edges and its cardinality are then checked explicitly. The checker
;;     neither mutates the search's tables nor owns runtime rows.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-index-sharing-certificate? (vector '(0) '(0 1))
;;                                              (vector 1 #f) (vector #f 0))
;;     ;; => #t, a maximum matching and tight endpoint cover
;;     ```
;;   %
(def (gerbil-ascent-index-sharing-certificate? sets left right)
  (let/cc reject
    (unless (and (vector? sets) (vector? left) (vector? right)
                 (= (vector-length sets) (vector-length left) (vector-length right)))
      (reject #f))
    (let* ((count (vector-length sets)) (ids (iota count))
           (widths (vector-map length sets))
           ;; Checker metadata is rebuilt from the supplied columns. It never
           ;; accepts the planner's precomputed successor graph as evidence.
           (members (make-vector count #f))
           (seen-left (make-vector count #f)) (seen-right (make-vector count #f))
           (pending []) (matched 0) (cover-count 0))
      (def (membership j)
        (or (vector-ref members j)
            (let (table (make-hash-table))
              (for-each (cut hash-put! table <> #t) (vector-ref sets j))
              (vector-set! members j table)
              table)))
      (def (below? i j)
        (and (< (vector-ref widths i) (vector-ref widths j))
             (let (table (membership j))
               (andmap (cut hash-key? table <>) (vector-ref sets i)))))
      (def (index? x) (or (eq? x #f) (and (exact-integer? x) (<= 0 x) (< x count))))
      (unless (and (andmap index? (vector->list left)) (andmap index? (vector->list right)))
        (reject #f))
      (for-each
       (lambda (i)
         (let ((j (vector-ref left i)) (owner (vector-ref right i)))
           (when j
             (unless (and (eqv? (vector-ref right j) i) (below? i j)) (reject #f))
             (set! matched (+ matched 1)))
           (when owner (unless (eqv? (vector-ref left owner) i) (reject #f)))
           (unless j
             (vector-set! seen-left i #t) (set! pending (cons i pending))))) ids)
      (let traverse ()
        (when (pair? pending)
          (let (i (car pending))
            (set! pending (cdr pending))
            (for-each
             (lambda (j)
               (when (and (below? i j) (not (vector-ref seen-right j)))
                 (vector-set! seen-right j #t)
                 (let (owner (vector-ref right j))
                   ;; An unmatched reachable right endpoint is an augmenting
                   ;; path and cannot certify maximum cardinality.
                   (unless owner (reject #f))
                   (unless (vector-ref seen-left owner)
                     (vector-set! seen-left owner #t)
                     (set! pending (cons owner pending)))))) ids))
          (traverse)))
      (for-each
       (lambda (i)
         (unless (vector-ref seen-left i) (set! cover-count (+ cover-count 1)))
         (when (vector-ref seen-right i) (set! cover-count (+ cover-count 1)))
         (for-each (lambda (j)
                     (when (and (below? i j) (vector-ref seen-left i)
                                (not (vector-ref seen-right j))) (reject #f))) ids)) ids)
      (= matched cover-count))))

;;; Sorted distinct columns admit a monotone merge, without allocating a
;;; membership table. This predicate is private to the planner; the checker
;;; derives membership independently from the original supplied column lists.
;; : (-> OrderedColumns OrderedColumns Boolean)
(def (ordered-subset? selected available)
  (cond ((null? selected) #t)
        ((null? available) #f)
        ((= (car selected) (car available))
         (ordered-subset? (cdr selected) (cdr available)))
        ((> (car selected) (car available))
         (ordered-subset? selected (cdr available)))
        (else #f)))

;;; One invocation owns the ordered sets and all strict-subset successors.
;;; Search and chain publication consume this descriptor, without recomputing
;;; column relationships at every alternating-path step.
(defstruct column-order (sets successors) final: #t)
;; : (-> (Vector OrderedColumns) ColumnOrder)
(def (compile-column-order sets)
  (let ((widths (vector-map length sets)) (ids (iota (vector-length sets))))
    (make-column-order sets
      (list->vector
       (map (lambda (i)
              (filter (lambda (j)
                        (and (< (vector-ref widths i) (vector-ref widths j))
                             (ordered-subset? (vector-ref sets i) (vector-ref sets j)))) ids)) ids)))))

;; : (-> OrderedColumns Boolean)
(def (distinct-ordered-columns? columns)
  (match columns
    ([left right . _]
     (and (< left right) (distinct-ordered-columns? (cdr columns))))
    (else #t)))

;;; Fix the tie order before maximum matching. Hash inventory order must not
;;; choose which of several equally minimal physical layouts is published.
;; : (-> OrderedColumns OrderedColumns Boolean)
(def (columns-lexicographic<? left right)
  (cond ((null? left) (pair? right))
        ((null? right) #f)
        ((< (car left) (car right)) #t)
        ((> (car left) (car right)) #f)
        (else (columns-lexicographic<? (cdr left) (cdr right)))))

;;; Admission owns detached sorted spines; an adjacent comparison rejects
;;; duplicates without allocating a second hash table for every requirement.
;; : (-> ColumnRequirements (Vector OrderedColumns))
(def (normalize-column-requirements requirements)
  (let (unique (make-hash-table))
    (for-each
     (lambda (columns)
       (unless (and (list? columns)
                    (andmap (lambda (n) (and (exact-integer? n) (>= n 0))) columns))
         (error "invalid index sharing columns" columns))
       (let (ordered (list-sort < columns))
         (unless (distinct-ordered-columns? ordered)
           (error "repeated index sharing columns" columns))
         (unless (null? ordered) (hash-put! unique ordered #t)))) requirements)
    (list->vector (list-sort columns-lexicographic<? (hash-keys unique)))))

;;; Maximum bipartite matching on strict subset edges yields a chain cover.
;;; Only chains with multiple logical requirements change physical storage;
;;; singleton chains retain the existing specialized hash representation.
;; : (-> ColumnRequirements IndexSharingLayout)
(def (gerbil-ascent-index-sharing-layout requirements)
  (let* ((sets (normalize-column-requirements requirements))
         (order (compile-column-order sets))
         (successors (column-order-successors order))
         (count (vector-length (column-order-sets order)))
         (left (make-vector count #f)) (right (make-vector count #f))
         (layout (make-hash-table)))
    (def (augment! i visited)
      (ormap
       (lambda (j)
         (and (not (vector-ref visited j))
              (begin
                (vector-set! visited j #t)
                (let (prior (vector-ref right j))
                  (and (or (not prior) (augment! prior visited))
                       (begin (vector-set! left i j) (vector-set! right j i) #t))))))
       (vector-ref successors i)))
    (for-each (lambda (i) (augment! i (make-vector count #f))) (iota count))
    (unless (gerbil-ascent-index-sharing-certificate? sets left right)
      (error "invalid index sharing maximum matching certificate"))
    (def visited (make-vector count #f))
    (for-each
     (lambda (i)
       (unless (vector-ref right i)
         (let chain ((j i) (members []) (permutation []))
           (when (vector-ref visited j) (error "index sharing chain repeats a requirement"))
           (vector-set! visited j #t)
           (let* ((columns (vector-ref sets j))
                  (next (vector-ref left j))
                  (extended (append permutation
                                    (filter (lambda (c) (not (member c permutation))) columns)))
                  (covered (cons columns members)))
             (if next
               (chain next covered extended)
               (when (pair? (cdr covered))
                 (for-each (lambda (c) (hash-put! layout c extended)) covered)))))))
     (iota count))
    (unless (andmap values (vector->list visited))
      (error "index sharing chains omit a requirement"))
    layout))

(defstruct shared-index (columns root ordinal views projection key-plans))
;;; Immutable column facts and one mutable scratch frame belong to one index.
;;; Neither metadata nor frame is a result row or a published bucket spine.
(defstruct column-projection (columns writes frame))
;;; A lookup plan owns only detached column facts and cleared private scratch.
(defstruct key-projection (physical writes frame) final: #t)

;;; Lookup keys are proper tuples; compare fields with Scheme's full value
;;; equality without treating the tuple spine as an arbitrary cyclic graph.
(def (key-sequence=? left right)
  (if (null? left) (null? right)
    (and (pair? right) (equal? (car left) (car right))
         (key-sequence=? (cdr left) (cdr right)))))
;;; Trie nodes retain either child maps or occurrence lists at full depth.
;;; Each occurrence has one increasing ordinal, so prefix traversal can restore
;;; exact relation order independently of hash traversal order and duplicates.
;; : (-> AdmittedRows NonemptyDistinctColumns SharedIndex)
(def (gerbil-ascent-shared-index-build rows columns)
  (let (index (make-shared-index columns (make-hash-table) 0
                                 (make-hash-table test: key-sequence=? hash: equal?-hash) #f #f))
    (gerbil-ascent-shared-index-extend! index (reverse rows))
    index))

;; : (-> SharedIndex AdmittedInsertionRows SharedIndex)
(def (gerbil-ascent-shared-index-extend! index rows)
  ;; Old result spines remain immutable. One successful batch invalidates all
  ;; aliases together; there is no shared mutable bucket between engine owners.
  (when (pair? rows)
    (shared-index-views-set! index (make-hash-table test: key-sequence=? hash: equal?-hash))
    (let* ((columns (shared-index-columns index))
           (width (length columns))
           ;; Sort reads, not trie levels. Each instruction carries the forward
           ;; cursor distance and the original physical destination slot.
           (projection (column-projection-for! index columns width))
           (writes (column-projection-writes projection))
           (frame (column-projection-frame projection)))
      (def (insert! node depth row ordinal)
        (let (key (vector-ref frame depth))
          (if (= (+ depth 1) width)
            (hash-put! node key (cons (cons ordinal row) (or (hash-get node key) [])))
            (let (child (or (hash-get node key)
                           (let (fresh (make-hash-table)) (hash-put! node key fresh) fresh)))
              (insert! child (+ depth 1) row ordinal)))))
      (for-each
       (lambda (row)
         (let (ordinal (+ (shared-index-ordinal index) 1))
           (fill-column-frame! row writes frame)
           (insert! (shared-index-root index) 0 row ordinal)
           (shared-index-ordinal-set! index ordinal))) rows)))
  index)

;;; Specialization depends on column identity, not row values. Empty batches
;;; never construct a projection. Borrowed columns can change: a detached
;;; snapshot guards reuse before gathering any row in the next nonempty batch.
;; : (-> SharedIndex NonemptyDistinctColumns Nat ColumnProjection)
(def (column-projection-for! index columns width)
  (let (prior (shared-index-projection index))
    (if (and prior (same-columns? columns (column-projection-columns prior))) prior
      (let (fresh (make-column-projection (list->vector columns)
                                         (column-writes columns) (make-vector width #f)))
        (shared-index-projection-set! index fresh)
        fresh))))

;;; Compare borrowed list metadata with a detached vector without allocating
;;; another column spine at each extension. Both length and order guard reuse.
;; : (-> NonemptyDistinctColumns (Vector Column) Boolean)
(def (same-columns? columns snapshot)
  (let compare ((remaining columns) (slot 0))
    (if (null? remaining) (= slot (vector-length snapshot))
      (and (< slot (vector-length snapshot))
           (equal? (car remaining) (vector-ref snapshot slot))
           (compare (cdr remaining) (+ slot 1))))))

;;; No user callback runs between gather and insert. Sort private metadata,
;;; never source columns or rows; row values are read afresh for every insert.
;; : (-> NonemptyDistinctColumns ColumnWrites)
(def (column-writes columns)
  ;; Every sorted pair and spine is private. Tail builders keep the column
  ;; projection from retaining additional construction continuations.
  (let gather ((remaining columns) (slot 0) (entries []))
    (if (null? remaining)
      (let (ordered (list-sort! (lambda (a b) (< (car a) (car b))) entries))
        (let steps ((remaining ordered) (position 0) (writes []))
          (if (null? remaining) (reverse! writes)
            (let (entry (car remaining))
              (steps (cdr remaining) (+ (car entry) 1)
                     (cons (cons (- (car entry) position) (cdr entry)) writes))))))
      (gather (cdr remaining) (+ slot 1)
              (cons (cons (car remaining) slot) entries)))))

;; : (-> AdmittedRow ColumnWrites PrivateFrame Void)
(def (fill-column-frame! row writes frame)
  (unless (null? writes)
    (let* ((instruction (car writes))
           (selected (list-tail row (car instruction))))
      (vector-set! frame (cdr instruction) (car selected))
      (fill-column-frame! (cdr selected) (cdr writes) frame))))

;;; Resolve logical positions once, then reuse the insertion gather protocol.
;;; Validation completes before metadata publication; values enter only later.
(def (compile-key-projection logical physical)
  (let (width (length logical))
    ;; This runs once per cached plan. Avoid a temporary ordinal hash table and
    ;; its entries; preserve first-occurrence lookup for repeated columns.
    (def (position-of column)
      (let seek ((remaining logical) (position 0))
        (and (pair? remaining)
             (if (= column (car remaining)) position
               (seek (cdr remaining) (+ position 1))))))
    (let gather ((remaining physical) (left width) (selected []) (prefix []))
      (if (zero? left)
        (make-key-projection (list->vector (reverse! prefix))
                            (column-writes (reverse! selected)) (make-vector width #f))
        (let (position (and (pair? remaining) (position-of (car remaining))))
          (unless position (error "logical index is not a physical prefix" logical physical))
          (gather (cdr remaining) (- left 1) (cons position selected) (cons (car remaining) prefix)))))))

(def (same-physical-prefix? physical snapshot)
  (let compare ((remaining physical) (slot 0))
    (or (= slot (vector-length snapshot))
        (and (pair? remaining) (equal? (car remaining) (vector-ref snapshot slot))
             (compare (cdr remaining) (+ slot 1))))))

;;; Metadata equality consumes natural ordinals, including large exact values.
;;; Keep hashing under Gerbil's existing structural hash contract.
(def (column-sequence=? left right)
  (if (null? left) (null? right)
    (and (pair? right) (= (car left) (car right))
         (column-sequence=? (cdr left) (cdr right)))))

(def (project-lookup-key index logical physical key)
  (let* ((plans (shared-index-key-plans index))
         (prior (and plans (hash-get plans logical)))
         (plan (if (and prior (same-physical-prefix? physical (key-projection-physical prior))) prior
                 (let (fresh (compile-key-projection logical physical))
                   (unless plans
                     (set! plans (make-hash-table hash: equal?-hash test: column-sequence=?))
                     (shared-index-key-plans-set! index plans))
                   ;; Never retain the caller's mutable logical column spine.
                   (hash-put! plans (append logical []) fresh) fresh)))
         (frame (key-projection-frame plan)))
    (fill-column-frame! key (key-projection-writes plan) frame)
    (let (owned (vector->list frame))
      ;; Metadata reuse must not retain a previous query's expression values.
      (vector-fill! frame #f)
      owned)))

;;; The only nonidentity two-column prefix is a swap. Express that algebraic
;;; shape directly, without admitting a cache or scratch frame for a tiny key.
(def (adapt-lookup-key index logical physical key)
  (match logical
    ([left right]
     (unless (and (pair? physical) (pair? (cdr physical))
                  (= left (cadr physical)) (= right (car physical)))
       (error "logical index is not a physical prefix" logical physical))
     (list (cadr key) (car key)))
    (else (project-lookup-key index logical physical key))))

;;; Logical key order may differ from the physical prefix permutation. Resolve
;;; that adapter without changing caller columns, keys, rows or published lists.
;; : (-> SharedIndex LogicalPrefixColumns LogicalKey OrderedRows)
(def (gerbil-ascent-shared-index-rows index columns key)
  (let (physical (shared-index-columns index))
    (unless (= (length columns) (length key)) (error "shared index key arity mismatch"))
    ;; Evaluate logical terms before entering this adapter. Reordering values
    ;; must never reorder expression callbacks or cache their results.
    (def (already-ordered? logical remaining)
      (or (null? logical)
          (and (pair? remaining) (= (car logical) (car remaining))
               (already-ordered? (cdr logical) (cdr remaining)))))
    ;; Thread one result tail through every branch. Only leaf bucket spines
    ;; are copied; ancestors never append an already collected subtree again.
    ;; Hash traversal order remains private: unique ordinals restore row order.
    ;; : (-> TrieNode RemainingColumns Occurrences Occurrences)
    (def (collect node remaining tail)
      (hash-fold
       (lambda (_ child records)
         (if (null? (cdr remaining)) (append child records)
           (collect child (cdr remaining) records))) tail node))
    (let* ((physical-key (if (already-ordered? columns physical) key
                            (adapt-lookup-key index columns physical key)))
           (cached (hash-get (shared-index-views index) physical-key)))
      (if cached (cdr cached)
        (let (rows
              (let lookup ((node (shared-index-root index)) (remaining physical) (key physical-key))
                (if (null? key)
                  (map cdr (list-sort (lambda (a b) (> (car a) (car b))) (collect node remaining [])))
                  (let (child (hash-get node (car key)))
                    (if (not child) []
                      (if (null? (cdr remaining)) (map cdr child)
                        (lookup child (cdr remaining) (cdr key))))))))
          ;; Cache membership owns its spine even on the ordered fast path.
          (hash-put! (shared-index-views index) (append physical-key []) (cons #t rows))
          rows)))))
