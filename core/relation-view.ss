;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Frozen row representations. Consumers own invocation-local traversal;
;;; views retain no cursor or mutable storage owner. Nested fields stay stable.
(import (only-in :std/list/list-builder with-list-builder))
(export relation-view? make-relation-view relation-view-count relation-view-units
        relation-view-identity relation-view-generation relation-view-revision relation-view-lane
        gerbil-ascent-view-with-export gerbil-ascent-view-bind gerbil-ascent-view-select gerbil-ascent-view-rows
        gerbil-ascent-explicit-view gerbil-ascent-lazy-explicit-view gerbil-ascent-view-union gerbil-ascent-view-difference
        gerbil-ascent-row-parts? gerbil-ascent-admitted-row-parts? gerbil-ascent-for-each-row-parts gerbil-ascent-visit-view-parts! gerbil-ascent-visit-admitted-view-parts!
        gerbil-ascent-for-each-row gerbil-ascent-any-row? gerbil-ascent-row-count
        gerbil-ascent-view-contains? make-rectangle gerbil-ascent-rectangle-view
        gerbil-ascent-write-rectangles!)
(defstruct relation-view (identity generation revision lane count units visit contains export parts))
(defstruct part-visitors (checked admitted))
;; Built-in products additionally own a direct selected-result collector.
;; Custom visitors keep their existing callback and ordering protocol.
(defstruct (rectangle-visitors part-visitors) (materialize) final: #t)
(defstruct row-stream (view columns key))
(defstruct rectangle (prefix left right))
(defstruct rectangle-bucket (members blocks count plain) final: #t)
;; Query-local owner lookup. Each coordinate uses its first fixed constraint;
;; no cache or traversal state escapes into the immutable captured view.
(defstruct rectangle-route (routes))
(defstruct (rectangle-query rectangle-route) (axes bindings scan?) final: #t)
(defstruct rectangle-selection (ordinal block members) final: #t)
;; : (-> FrozenView Symbol SourceGeneration Natural Symbol FrozenView)
(def (gerbil-ascent-view-bind view identity generation revision lane)
  (make-relation-view identity generation revision lane (relation-view-count view)
    (relation-view-units view) (relation-view-visit view) (relation-view-contains view) (relation-view-export view) (relation-view-parts view)))
;; Private ordered export can replay a frozen injection cut without a tuple cache.
(def (gerbil-ascent-view-with-export view export)
  (make-relation-view (relation-view-identity view) (relation-view-generation view)
    (relation-view-revision view) (relation-view-lane view) (relation-view-count view)
    (relation-view-units view) (relation-view-visit view) (relation-view-contains view) export (relation-view-parts view)))
;; : (-> RowVisitor (Or Rows FrozenView RowStream) Void)
(def (gerbil-ascent-for-each-row consume rows)
  (cond ((relation-view? rows) ((relation-view-visit rows) [] [] consume))
        ((row-stream? rows) ((relation-view-visit (row-stream-view rows))
                            (row-stream-columns rows) (row-stream-key rows) consume))
        (else (for-each consume rows))))
;; : (-> RowPredicate (Or Rows FrozenView RowStream) Boolean)
(def (gerbil-ascent-any-row? predicate rows)
  (call/cc (lambda (done)
    (gerbil-ascent-for-each-row (lambda (row) (when (predicate row) (done #t))) rows) #f)))
;; : (-> (Or Rows FrozenView) Natural)
(def (gerbil-ascent-row-count rows)
  (if (relation-view? rows) (relation-view-count rows) (length rows)))
;; : (-> FrozenView Columns Key (Or FrozenView RowStream))
(def (gerbil-ascent-view-select view columns key)
  (if (and (null? columns) (null? key)) view
    (make-row-stream view columns key)))
;; Compiled consumers bind fields directly; no temporary Cartesian row is built.
;; : (-> RowSource Boolean)
(def (gerbil-ascent-row-parts? rows)
  (and (cond ((relation-view? rows) (relation-view-parts rows))
             ((row-stream? rows) (relation-view-parts (row-stream-view rows))) (else #f)) #t))
;; Checked custom visitors do not establish exact canonical key selection.
;; A mixed union retains that distinction through arbitrarily nested cuts.
(def (gerbil-ascent-admitted-row-parts? view)
  (and (relation-view? view)
       (let (parts (relation-view-parts view))
         (and (part-visitors? parts) (part-visitors-admitted parts) #t))))
;; : (-> PartVisitor RowSource Void)
(def (gerbil-ascent-for-each-row-parts consume rows)
  (if (relation-view? rows) (gerbil-ascent-visit-view-parts! rows [] [] consume)
    (gerbil-ascent-visit-view-parts! (row-stream-view rows)
      (row-stream-columns rows) (row-stream-key rows) consume)))
;; Synchronous indexed consumers own traversal. Custom parts retain the
;; checked three-argument protocol; built-in visitors carry admission separately.
;; : (-> FrozenView Columns Key PartVisitor Void)
(def (gerbil-ascent-visit-view-parts! view columns key consume)
  (let (parts (relation-view-parts view))
    ((if (part-visitors? parts) (part-visitors-checked parts) parts) columns key consume)))
;; Only the canonical compiled index owner supplies admitted columns and keys.
;; : (-> BuiltinView AdmittedColumns AdmittedKey PartVisitor Void)
(def (gerbil-ascent-visit-admitted-view-parts! view columns key consume)
  (unless (gerbil-ascent-admitted-row-parts? view)
    (error "ASCENT view lacks admitted parts"))
  ((part-visitors-admitted (relation-view-parts view)) columns key consume))
;; : (-> FrozenView Row Boolean)
(def (gerbil-ascent-view-contains? view row)
  ((relation-view-contains view) row))
;; : (-> FrozenView Rows)
(def (materialize-rows visit)
  ;; The invocation owns only this outer spine. Visitors control tuple
  ;; construction; frozen member and journal spines are never reversed.
  (with-list-builder (collect!)
    (visit collect!)))
;; Selected materialization shares the owned collector with fallback exports.
;; Complete export and explicit query have distinct ordering contracts.
(def gerbil-ascent-view-rows
  (case-lambda
    ((view)
     (if (relation-view-export view)
       ((relation-view-export view))
       (materialize-rows (cut (relation-view-visit view) [] [] <>))))
    ((view columns key)
     (let (parts (relation-view-parts view))
       (if (rectangle-visitors? parts)
         ((rectangle-visitors-materialize parts) columns key)
         (materialize-rows (cut (relation-view-visit view) columns key <>)))))))
;; : (-> Row Columns Key Boolean)
(def (matches-key? row columns key)
  (andmap (lambda (column value) (equal? (list-ref row column) value)) columns key))
;; A query owns its relative offsets; each row owns its traversal cursor.
;; Preserve condition order, including duplicate columns and short-circuiting.
;; Unordered or malformed selectors retain the general list-ref protocol.
(def (ordered-key-offsets columns key)
  (and (list? columns) (list? key) (= (length columns) (length key))
       (let/cc unordered
         (let (previous 0)
           (map (lambda (column)
                  (unless (and (exact-integer? column) (>= column previous))
                    (unordered #f))
                  (let (offset (- column previous))
                    (set! previous column)
                    offset)) columns)))))
(def (matches-offset-key? row offsets key)
  (or (null? offsets)
      (let (rest (list-tail row (car offsets)))
        (and (equal? (list-ref rest 0) (car key))
             (matches-offset-key? rest (cdr offsets) (cdr key))))))
(def (compile-explicit-key-match columns key)
  (let (offsets (ordered-key-offsets columns key))
    (if offsets
      (cut matches-offset-key? <> offsets key)
      (cut matches-key? <> columns key))))
;; Compare without allocating a temporary prefix or importing a prelude binding.
(def (matches-prefix? row prefix)
  (or (null? prefix)
      (and (pair? row) (equal? (car row) (car prefix))
           (matches-prefix? (cdr row) (cdr prefix)))))
;; : (-> Rows Natural FrozenView)
(def (gerbil-ascent-explicit-view rows count)
  (gerbil-ascent-lazy-explicit-view
    (map (lambda (row) (map values row)) rows) count))
;; Persistent engine rows are borrowed read-only; every emitted row spine is
;; detached. Count observation never forces the ordering promise.
;; : (-> (Or Rows (Promise Rows)) Natural FrozenView)
(def (gerbil-ascent-lazy-explicit-view snapshot count)
  (def (rows) (if (promise? snapshot) (force snapshot) snapshot))
  (make-relation-view #f #f 0 'total count count
    (lambda (columns key consume)
      (let (matches? (compile-explicit-key-match columns key))
        (for-each (lambda (row) (when (matches? row) (consume (map values row)))) (rows))))
    (lambda (row) (and (member row (rows)) #t)) #f #f))
;; The caller establishes disjoint facts; this is not a general Set union.
;; : (-> FrozenView FrozenView FrozenView)
(def (gerbil-ascent-view-union left right)
  (make-relation-view #f #f 0 'delta
    (+ (relation-view-count left) (relation-view-count right))
    (+ (relation-view-units left) (relation-view-units right))
    (lambda (columns key consume)
      ((relation-view-visit left) columns key consume)
      ((relation-view-visit right) columns key consume))
    (lambda (row) (or (gerbil-ascent-view-contains? left row)
                     (gerbil-ascent-view-contains? right row))) #f
    (and (relation-view-parts left) (relation-view-parts right)
         (make-part-visitors
           (lambda (columns key consume)
             (gerbil-ascent-visit-view-parts! left columns key consume)
             (gerbil-ascent-visit-view-parts! right columns key consume))
           (and (gerbil-ascent-admitted-row-parts? left) (gerbil-ascent-admitted-row-parts? right)
             (lambda (columns key consume)
               (gerbil-ascent-visit-admitted-view-parts! left columns key consume)
               (gerbil-ascent-visit-admitted-view-parts! right columns key consume)))))))
;; Monotone cuts with row parts; caller establishes older is a subset of newer.
;; : (-> FrozenView FrozenView Natural FrozenView)
(def (gerbil-ascent-view-difference newer older count)
  (unless (and (exact-integer? count) (>= count 0)
               (gerbil-ascent-row-parts? newer) (gerbil-ascent-row-parts? older)
               (= count (- (relation-view-count newer) (relation-view-count older))))
    (error "ASCENT view difference requires coherent part cuts"))
  (let ((admitted? (and (gerbil-ascent-admitted-row-parts? newer)
                         (gerbil-ascent-admitted-row-parts? older)))
        (indexed? (rectangle-visitors? (relation-view-parts older))))
      ;; Only the private product carrier guarantees contains/parts agreement.
      ;; Custom part visitors retain their full checked/admitted probe contract.
      (def (present? row admitted?)
        (if indexed? (gerbil-ascent-view-contains? older row)
          (let (found? #f)
            ((if admitted? gerbil-ascent-visit-admitted-view-parts! gerbil-ascent-visit-view-parts!)
              older (case (length row) ((2) '(0 1)) ((3) '(0 1 2)) (else (iota (length row))))
              row (lambda (_prefix _left _right) (set! found? #t)))
            found?)))
      (def (parts columns key consume admitted?)
        ((if admitted? gerbil-ascent-visit-admitted-view-parts! gerbil-ascent-visit-view-parts!)
          newer columns key
          (lambda (prefix left right)
            (unless (present? (append prefix (list left right)) admitted?)
              (consume prefix left right)))))
      (make-relation-view #f #f 0 'delta count
        (+ (relation-view-units newer) (relation-view-units older))
        (lambda (columns key consume)
          (parts columns key (lambda (prefix left right) (consume (append prefix (list left right)))) #f))
        (lambda (row) (and (gerbil-ascent-view-contains? newer row)
                          (not (gerbil-ascent-view-contains? older row)))) #f
        (make-part-visitors
          (lambda (columns key consume) (parts columns key consume #f))
          (and admitted? (lambda (columns key consume) (parts columns key consume #t)))))))
;; : (-> Value Natural Columns Key Boolean)
(def (matches-coordinate? value coordinate columns key)
  (andmap (lambda (column selected) (or (not (= column coordinate)) (equal? value selected))) columns key))
;; : (-> Members Natural Columns Key Members)
(def (captured-member query members coordinate value)
  (if (not (rectangle-query? query))
    (captured-owner-member
      (or (hash-get (vector-ref (rectangle-route-routes query) coordinate) value) []) members)
   (using (query :- rectangle-query)
    (def hits (or (hash-get (vector-ref query.routes coordinate) value) []))
    (cond
      ((null? hits) #f)
      ((null? (cdr hits))
       (and (eq? (rectangle-bucket-members (cdar hits)) members) (caar hits)))
      (query.scan? (captured-owner-member hits members))
      (else
       (unless query.axes (set! query.axes (make-vector (vector-length query.routes) #f)))
       (let (owners (or (vector-ref query.axes coordinate)
                       (let (table (make-hash-table-eq))
                         (for-each (lambda (hit)
                           (hash-put! table (rectangle-bucket-members (cdr hit)) (car hit))) hits)
                         (vector-set! query.axes coordinate table) table)))
         (hash-get owners members)))))))
;; A narrow descriptor selection does not justify indexing every unrelated
;; owner with the same value. Borrow the stored singleton without a new table.
(def (captured-owner-member hits members)
  (match hits
    ([] #f)
    ([[singleton . bucket] . rest]
     (if (eq? members (rectangle-bucket-members bucket)) singleton
       (captured-owner-member rest members)))))
;; A point publishes a scalar, but still borrows its stored representative.
;; Long axes use the frozen owner route; their cost must not depend on the
;; requested value's position in the component membership list.
(def (captured-point-member routes members coordinate value)
  (match members
    ([a b c d _ . _]
     ;; Probe the bounded head already admitted by this representation test.
     ;; A miss uses the frozen route, never scans the long remaining spine.
     (cond ((equal? value a) members)
           ((equal? value b) (cdr members))
           ((equal? value c) (cddr members))
           ((equal? value d) (cdddr members))
           (else (captured-owner-member
                   (or (hash-get (vector-ref routes coordinate) value) []) members))))
    (else (member value members))))
;; Bind each coordinate once. Key tails distinguish a fixed #f from an unbound
;; slot, retain the first requested value, and allocate no per-binding cells.
;; Range admission checks every coordinate, even after an absent/conflicting key.
;; Admit finite binary/group layouts before constructing a consumer. Scoped
;; syntax makes the binding and publication extents explicit without a plan
;; object or a dynamically allocated continuation for each condition.
(defrule (with-compact-bindings offset columns key group left right admitted rejected)
  (let ((selectors columns) (keys key))
    (unless (and (list? selectors) (list? keys))
      (error "invalid ASCENT UF view key"))
    ;; The captured schema chooses a lexical cursor, not a per-condition
    ;; comparator. Case admits only the exact integer coordinate literals.
    (defrule (walk group-column left-column right-column group?)
      (let bind ((pending selectors) (values keys) (group #f) (left #f) (right #f)
                 (conflict? #f) (outside? #f))
        (cond
          ((null? pending)
           (unless (null? values) (error "invalid ASCENT UF view key"))
           (when outside? (error "invalid ASCENT UF view column"))
           (if conflict? rejected admitted))
          ((null? values) (error "invalid ASCENT UF view key"))
          (else
           (let ((column (car pending)) (rest (cdr pending)))
             (defrule (slot previous next-group next-left next-right)
               (bind rest (cdr values) next-group next-left next-right
                 (or conflict? (and previous (not (equal? (car previous) (car values))))) outside?))
             (case column
               ((group-column)
                (if group? (slot group (or group values) left right)
                  (error "invalid ASCENT UF view key")))
               ((left-column) (slot left group (or left values) right))
               ((right-column) (slot right group left (or right values)))
               (else
                ;; Syntax rejection dominates range/conflict rejection even
                ;; when it occurs in a later suffix; no consumer exists yet.
                (unless (and (exact-integer? column) (>= column 0))
                  (error "invalid ASCENT UF view key"))
                (bind rest (cdr values) group left right conflict? #t))))))))
    (if (= offset 0) (walk -1 0 1 #f) (walk 0 1 2 #t))))
(def (compile-rectangle-bindings width columns key)
  ;; Admission precedes short-circuiting: a conflict cannot hide an invalid
  ;; later coordinate. Ordinary tail recursion needs no escape continuation.
  (unless (andmap (lambda (column) (< column width)) columns)
    (error "invalid ASCENT UF view column"))
  (let (bindings (make-vector width #f))
      (let bind ((columns columns) (key key))
        (match columns
          ([] bindings)
          ([column . rest]
           (let (previous (vector-ref bindings column))
             (and (or (not previous) (equal? (car previous) (car key)))
                  (begin
                    (unless previous (vector-set! bindings column key))
                    (bind rest (cdr key))))))))))
(def (matches-bound-prefix? prefix bindings coordinate)
  (match prefix
    ([] #t)
    ([value . rest]
     (let (binding (vector-ref bindings coordinate))
       (and (or (not binding) (equal? value (car binding)))
            (matches-bound-prefix? rest bindings (+ coordinate 1)))))))
(defrule (select-members-by-column members coordinate columns key probe retain)
  (let find ((remaining columns) (values key))
    (cond ((null? remaining) members)
          ((= (car remaining) coordinate)
           (let (present (probe (car values)))
             (if (and present (matches-coordinate? (car present) coordinate columns key))
               (retain present) [])))
          (else (find (cdr remaining) (cdr values))))))
;; Keep scan-only probes lexical: split C hosts otherwise add generic calls
;; at each selected axis. Bind every macro argument exactly once.
(defrule (selected-scan-members members coordinate columns key)
  (let ((axis members) (index coordinate) (constraints columns) (values key))
    (defrule (probe value) (member value axis))
    (defrule (retain present) (list (car present)))
    (select-members-by-column axis index constraints values probe retain)))
(def (selected-members members coordinate columns key routes)
  (defrule (probe value)
    (if routes (captured-member routes members coordinate value) (member value members)))
  (defrule (retain present) (if routes present (list (car present))))
  (if (and (rectangle-query? routes) (rectangle-query-bindings routes))
    (let (binding (vector-ref (rectangle-query-bindings routes) coordinate))
      (if binding (or (captured-member routes members coordinate (car binding)) []) members))
    (select-members-by-column members coordinate columns key probe retain)))
(def (visit-right-members prefix left rights consume)
  (unless (null? rights)
    (consume prefix left (car rights))
    (visit-right-members prefix left (cdr rights) consume)))
(def (visit-left-members prefix lefts rights consume)
  (unless (null? lefts)
    (visit-right-members prefix (car lefts) rights consume)
    (visit-left-members prefix (cdr lefts) rights consume)))

;; Expand directly into the invocation-owned native list builder. Tuple
;; syntax and the builder macro are bound once; no callback runs per row.
(defrule (collect-rectangle-product left right lefts rights emit tuple)
  (let collect-left ((pending lefts))
    (match pending
      ([] (void))
      ([left . tail]
       (let collect-right ((remaining rights))
         (match remaining
           ([] (collect-left tail))
           ([right . rest]
            (emit tuple)
            (collect-right rest))))))))
(def (materialize-rectangles blocks)
  (with-list-builder (collect!)
    (for-each (lambda (block)
      (with (((rectangle prefix lefts rights) block))
        (match prefix
          ([] (collect-rectangle-product left right lefts rights collect! (list left right)))
          ([group] (collect-rectangle-product left right lefts rights collect! (list group left right)))
          (else (collect-rectangle-product left right lefts rights collect! (append prefix (list left right)))))))
      blocks)))
 ;; An admitted uniform width chooses the public tuple constructor once.
(def (rectangle-row-writer width consume)
  (case width
    ((2) (lambda (_prefix left right) (consume (list left right))))
    ((3) (lambda (prefix left right) (consume (list (car prefix) left right))))
    (else (lambda (prefix left right) (consume (append prefix (list left right)))))))
;; gerbil-ascent-write-rectangles!
;; : (forall (r) (-> [(Rectangle r)] (-> [r] Void) Void))
;; : (-> [Rectangle] RowWriter Void)
;; | doc m%
;;     Stream admitted rectangles in descriptor/member order into fresh rows.
;;     Select each fixed row constructor before product traversal. Member and
;;     prefix spines remain borrowed; the caller owns emitted row spines.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-write-rectangles! (list (make-rectangle [] '(1) '(2))) displayln)
;;     ;; => writes the fresh row (1 2)
;;     ```
;;   %
(def (gerbil-ascent-write-rectangles! blocks consume)
  (for-each (lambda (block)
    (let* ((prefix (rectangle-prefix block))
           (write (match prefix
                    ([] (lambda (_prefix a b) (consume (list a b))))
                    ([group] (lambda (_prefix a b) (consume (list group a b))))
                    (else (lambda (prefix a b) (consume (append prefix (list a b))))))))
      (visit-left-members prefix (rectangle-left block) (rectangle-right block) write))) blocks))
;; : (-> Rectangle Columns Key PartVisitor Void)
(defrule (define-checked-rectangle-visitor name admitted)
  (def (name block columns key consume (routes #f) (expand visit-left-members))
    (let (offset (length (rectangle-prefix block)))
      (unless (andmap (lambda (column) (< column (+ offset 2))) columns)
        (error "invalid ASCENT UF view column")))
    (admitted block columns key consume routes expand)))
(defrule (with-admitted-rectangle-parts block columns key consume routes expand routed?)
  (let* ((prefix (rectangle-prefix block)) (offset (length prefix)))
    (when (if (and routed? (rectangle-query? routes) (rectangle-query-bindings routes))
            (matches-bound-prefix? prefix (rectangle-query-bindings routes) 0)
            (andmap (lambda (column value)
                      (or (>= column offset) (equal? (list-ref prefix column) value))) columns key))
      (let ((lefts (if routed?
                     (selected-members (rectangle-left block) offset columns key routes)
                     (selected-scan-members (rectangle-left block) offset columns key)))
            (rights (if routed?
                      (selected-members (rectangle-right block) (+ offset 1) columns key routes)
                      (selected-scan-members (rectangle-right block) (+ offset 1) columns key))))
        (expand prefix lefts rights consume)))))
(defrule (define-admitted-rectangle-visitor name routed?)
  (def (name block columns key consume routes (expand visit-left-members))
    (with-admitted-rectangle-parts block columns key consume routes expand routed?)))
;; Both visitors share the complete expansion syntax. The scan macro also
;; keeps the caller's publisher lexical instead of passing it through optional
;; argument functions. Checks, stored representatives and callback order stay
;; in the same sequence; only routed visitors need runtime procedure values.
(define-admitted-rectangle-visitor visit-admitted-rectangle-parts #t)
(defrule (visit-admitted-scan-rectangle-parts block columns key consume routes expand)
  (let ((owner block) (constraints columns) (keys key) (visitor consume)
        (query routes) (emit expand))
    (with-admitted-rectangle-parts owner constraints keys visitor query emit #f)))
(define-checked-rectangle-visitor visit-rectangle-parts visit-admitted-rectangle-parts)
(defrule (visit-scan-rectangle-parts block columns key consume routes expand)
  (let ((owner block) (constraints columns) (keys key) (visitor consume) (query routes) (emit expand))
    (let (offset (length (rectangle-prefix owner)))
      (unless (andmap (lambda (column) (< column (+ offset 2))) constraints)
        (error "invalid ASCENT UF view column")))
    (visit-admitted-scan-rectangle-parts owner constraints keys visitor query emit)))
;; Build once from owned spines. Each component contributes its members once
;; per coordinate; the buckets retain descriptor references, never pair tuples.
;; Readers only inspect these private tables after construction.
(def (rectangle-routing blocks small? shared?)
  ;; Bind the constructor profile once. The expanded large path retains the
  ;; native identity-table loop without a tiny-policy branch per insertion.
  (defrule (build tiny?)
    (let* ((arity (foldl (lambda (block n) (max n (+ 2 (length (rectangle-prefix block))))) 0 blocks))
           (limit (if shared? (- arity 1) arity))
           (owners (make-vector arity #f))
           (routes (make-vector arity #f)))
      ;; A uniform self-component cut owns one immutable endpoint route. Its
      ;; two coordinates borrow that same route after publication; per-query
      ;; cursors and owner caches remain separate and invocation-local.
      (let initialize ((column 0))
        (when (< column limit)
          (vector-set! owners column (if tiny? [] (make-hash-table-eq)))
          (vector-set! routes column (make-hash-table))
          (initialize (+ column 1))))
      (when shared?
        (vector-set! owners limit (vector-ref owners (- limit 1)))
        (vector-set! routes limit (vector-ref routes (- limit 1))))
      (for-each (lambda (block ordinal)
        (let* ((prefix (rectangle-prefix block)) (offset (length prefix)))
          (def (add! column identity members)
            (let* ((table (vector-ref owners column))
                   (bucket (or (if tiny? (alet (entry (assq identity table)) (cdr entry))
                                 (hash-get table identity))
                               (let (fresh (make-rectangle-bucket members [] 0 []))
                                 (if tiny? (vector-set! owners column (cons (cons identity fresh) table))
                                   (hash-put! table identity fresh)) fresh))))
              (rectangle-bucket-blocks-set! bucket
                (cons (cons ordinal block) (rectangle-bucket-blocks bucket)))
              (rectangle-bucket-count-set! bucket (+ 1 (rectangle-bucket-count bucket)))))
          (for-each (lambda (column value) (add! column prefix (list value))) (iota offset) prefix)
          (add! offset (rectangle-left block) (rectangle-left block))
          (unless shared? (add! (+ offset 1) (rectangle-right block) (rectangle-right block))))) blocks (iota (length blocks)))
      (for-each (lambda (column)
        (def (publish! _ bucket)
          (using (bucket :- rectangle-bucket)
            (set! bucket.blocks (reverse bucket.blocks))
            (set! bucket.plain (map cdr bucket.blocks))
            (let (table (vector-ref routes column))
              (for-each (lambda (member)
                (let (hits (or (hash-get table member) []))
                  ;; Construction finishes this bucket before any other bucket
                  ;; inserts. A duplicate must therefore have this owner at the
                  ;; head; retain its first stored value without scanning hits.
                  (unless (and (pair? hits) (eq? (cdar hits) bucket))
                    (hash-put! table member (cons (cons (list member) bucket) hits))))) bucket.members))))
        (if tiny?
          (for-each (lambda (entry) (publish! (car entry) (cdr entry))) (vector-ref owners column))
          (hash-for-each publish! (vector-ref owners column)))) (iota limit))
      routes))
  (if small? (build #t) (build #f)))
;; Choose the smallest descriptor bucket, then preserve captured traversal order.
;; Other coordinates (including repeated constraints) remain checked by visitor.
(def (routed-rectangles routes blocks columns key (uniform? #f) (bindings #f))
  (if (null? columns) blocks
    (let ((selected #f) (cost +inf.0))
      (def (choose! column value)
        (when (>= column (vector-length routes)) (error "invalid ASCENT UF view column"))
        ;; A single descriptor is already minimal for traversal. Remaining
        ;; coordinates still receive range checks here and value checks in
        ;; the visitor, including absent keys and repeated constraints.
        (when (> cost 1)
          (let* ((buckets (or (hash-get (vector-ref routes column) value) []))
                 (size (foldl (lambda (hit n) (+ n (rectangle-bucket-count (cdr hit)))) 0 buckets)))
            (when (< size cost) (set! selected buckets) (set! cost size)))))
      (if bindings
        (let scan ((coordinate 0))
          (when (< coordinate (vector-length bindings))
            (let (binding (vector-ref bindings coordinate))
              (when binding (choose! coordinate (car binding))))
            (scan (+ coordinate 1))))
        (for-each choose! columns key))
      (cond ((null? selected) [])
            ((null? (cdr selected)) (rectangle-bucket-plain (cdar selected)))
            ;; Gather plus ordering costs k log k; a uniform captured scan
            ;; visits n descriptors directly in publication order. Every row
            ;; constraint remains checked, including absent/repeated keys.
            ((and uniform? (>= (* cost (integer-length cost)) (length blocks))) blocks)
            (else (map cdr (list-sort (lambda (a b) (< (car a) (car b)))
                            (apply append (map (lambda (hit) (rectangle-bucket-blocks (cdr hit))) selected)))))))))
;; Routing narrows descriptors; exact membership still belongs to each captured
;; rectangle, including equal endpoint values shared by unrelated groups.
(def (bucket-owner? members hits)
  (match hits
    ([] #f)
    ([[_ . bucket] . rest]
     (or (eq? members (rectangle-bucket-members bucket))
         (bucket-owner? members rest)))))
(def (indexed-axis-member? routes members coordinate value)
  ;; Route equality alone is insufficient: equal values in different owners
  ;; must not combine into a nonexistent Cartesian product. Borrow buckets.
  (match members
    ([_ _ _ _ _ . _]
     (bucket-owner? members (or (hash-get (vector-ref routes coordinate) value) [])))
    (else (and (member value members) #t))))
(def (rectangle-contains? block row width routes)
  (let* ((prefix (rectangle-prefix block)) (offset (length prefix)))
    (and (= width (+ offset 2)) (matches-prefix? row prefix)
         (if routes
           (and (indexed-axis-member? routes (rectangle-left block) offset (list-ref row offset))
                (indexed-axis-member? routes (rectangle-right block) (+ offset 1) (list-ref row (+ offset 1))))
           (and (member (list-ref row offset) (rectangle-left block))
                (member (list-ref row (+ offset 1)) (rectangle-right block)))) #t)))
(def (rectangles-contain? blocks row width routes)
  (match blocks
    ([] #f)
    ([block . rest]
     (or (rectangle-contains? block row width routes)
         (rectangles-contain? rest row width routes)))))
;; Rectangles must be disjoint; member spines belong to the captured cut.
;; : (-> (List Rectangle) Natural Natural Boolean FrozenView)
;; Multiple right owners publish ordered descriptor selections once. Each plan
;; spine is owned by construction and borrows immutable bucket references.
(def (ordered-right-plans routes blocks uniform?)
  (and routes uniform?
    (hash-find (lambda (_ hits) (pair? (cdr hits)))
      (vector-ref routes (- (vector-length routes) 1)))
    (let ((plans (make-hash-table)) (width (length blocks)) (workspace #f))
      (hash-for-each (lambda (value hits)
          ;; Bucket membership and ordinals are already frozen. The lexical
          ;; publisher selects a representation once, before visiting entries.
          (defrule (owner-selections publish!)
            (for-each (lambda (hit)
              (with (([singleton . bucket] hit))
                (for-each (lambda (entry)
                  (publish! (car entry) (cdr entry) singleton))
                  (rectangle-bucket-blocks bucket)))) hits))
        (when (pair? (cdr hits))
          (let* ((count (foldl (lambda (hit n) (+ n (rectangle-bucket-count (cdr hit)))) 0 hits))
                 ;; An ordinal scan avoids sorting dense/repeated-owner plans.
                 ;; Sparse keys retain gather/sort instead of scanning the cut.
                 (dense? (>= (* count (integer-length count)) width))
                 (selected
                  (if dense?
                    (let ()
                      (defrule (place! ordinal block singleton)
                        (vector-set! workspace ordinal (make-rectangle-selection ordinal block singleton)))
                      (unless workspace (set! workspace (make-vector width #f)))
                      (owner-selections place!)
                      (with-list-builder (emit!)
                        (let publish ((ordinal 0))
                          (when (< ordinal width)
                            (let (entry (vector-ref workspace ordinal))
                              (when entry
                                ;; Clear every occupied slot before the next
                                ;; key; no scratch escapes in the frozen plan.
                                (vector-set! workspace ordinal #f)
                                (emit! entry)))
                            (publish (+ ordinal 1))))))
                    (with-list-builder (emit!)
                      (defrule (collect! ordinal block singleton)
                        (emit! (make-rectangle-selection ordinal block singleton)))
                      (owner-selections collect!)))))
            (hash-put! plans value
              (if dense? selected
                (list-sort! (lambda (a b) (< (rectangle-selection-ordinal a)
                                           (rectangle-selection-ordinal b))) selected))))))
        (vector-ref routes (- (vector-length routes) 1)))
      plans)))
(def (gerbil-ascent-rectangle-view blocks count units (indexed? #f))
  (let* ((small? (or (null? blocks) (null? (cdr blocks)) (null? (cddr blocks))))
         (uniform? (or (null? blocks)
                       (let (prefix (rectangle-prefix (car blocks)))
                         ;; Preserve first-prefix shape validation. Captured
                         ;; aliases need no repeated prefix-spine traversal.
                         (length prefix)
                         (andmap (lambda (block)
                           (let (other (rectangle-prefix block))
                             (or (eq? prefix other) (= (length prefix) (length other))))) blocks))))
         (self? (and indexed? uniform? (pair? blocks)
                     (andmap (lambda (block) (eq? (rectangle-left block) (rectangle-right block))) blocks)))
         (routes (and indexed? (pair? blocks) (rectangle-routing blocks small? self?)))
         ;; The tiny read-only route carrier borrows stored singleton values.
         ;; It has no query keys, owner index, cursor or mutable reader state.
         (scan-route (and routes small? (make-rectangle-route routes)))
         ;; One or two descriptors are cheaper to scan than route and gather.
         (membership-routes (and routes (pair? (cdr blocks)) (pair? (cddr blocks)) routes))
         (query-columns (and membership-routes (iota (vector-length membership-routes))))
         ;; Complete keys bind every coordinate once. Reuse the existing
         ;; membership schema and borrow owner hits without query state.
         (complete-columns (and routes uniform? (or query-columns (iota (vector-length routes)))))
         (right-plans (and (not small?) (ordered-right-plans routes blocks uniform?)))
         ;; A self-component cut has the same owner axis on both sides.
         ;; Its frozen descriptor plan can serve either endpoint unchanged.
         (left-plans (and self? right-plans)))
  (def (selected columns key)
    (cond
      ((and routes uniform? small?)
       ;; A tiny cut is already a bounded ordered candidate set. Admission
       ;; needs every range check, but no bucket costing or gather closure.
       (unless (andmap (lambda (column) (< column (vector-length routes))) columns)
         (error "invalid ASCENT UF view column"))
       blocks)
      (routes (routed-rectangles routes blocks columns key uniform?))
      (else blocks)))
  (def (validate-key! columns key)
    (unless (and (list? columns) (list? key) (= (length columns) (length key))
                 (andmap (lambda (column) (and (exact-integer? column) (>= column 0))) columns))
      (error "invalid ASCENT UF view key")))
  (def (planned-axis column key)
    (let (plans (if (= column (- (vector-length routes) 2)) left-plans right-plans))
      (and plans (hash-get plans key))))
  (def (visit-axis-plan hits consume left? expand)
    (for-each (lambda (hit)
      (using (hit :- rectangle-selection)
        (expand (rectangle-prefix hit.block)
          (if left? hit.members (rectangle-left hit.block))
          (if left? (rectangle-right hit.block) hit.members) consume))) hits))
  (def (visit-indexed-axis columns key consume (expand visit-left-members))
    (and routes uniform? (pair? columns) (null? (cdr columns))
         (let* ((column (car columns)) (left-column (- (vector-length routes) 2)))
           (and (or (= column left-column) (= column (+ left-column 1)))
             (let (hits (or (hash-get (vector-ref routes column) (car key)) []))
               (cond
                 ((null? hits) #t)
                 ((null? (cdr hits))
                  (let ((members (caar hits)) (bucket (cdar hits)))
                    (for-each (lambda (block)
                      (expand (rectangle-prefix block)
                        (if (= column left-column) members (rectangle-left block))
                        (if (= column left-column) (rectangle-right block) members) consume))
                      (rectangle-bucket-plain bucket)))
                  #t)
                 ((planned-axis column (car key)) =>
                  (lambda (plans) (visit-axis-plan plans consume (= column left-column) expand) #t))
                 (else #f)))))))
  ;; Both callers have already admitted the complete column schema.
  ;; Tiny cuts therefore need neither another schema comparison nor range scan.
;; BEGIN GENERATED LOOKUP ADMISSION
  (def (visit-admitted-complete-key columns key point)
    (let* ((offset (- (vector-length routes) 2))
           (endpoints (list-tail key offset)))
      (for-each (lambda (block)
        (with (((rectangle prefix left right) block))
          (when (matches-prefix? key prefix)
            ;; Return the candidate's stored values directly, without
            ;; allocating selected singleton spines or product collectors.
            (let ((a (captured-point-member routes left offset (car endpoints)))
                  (b (captured-point-member routes right (+ offset 1) (cadr endpoints))))
              (when (and a b) (point prefix (car a) (car b))))))) (if small? blocks (selected columns key)))
      #t))
  (def (visit-complete-key columns key point)
    (and complete-columns (equal? columns complete-columns)
       (visit-admitted-complete-key columns key point)))
;; END GENERATED LOOKUP ADMISSION
  ;; Intersect immutable descriptor plans with invocation-local list cursors.
  ;; Equal ordinals identify the same captured descriptor, not equal values
  ;; from unrelated owners. No owner table or query record is constructed.
  ;; Fully bound endpoints publish one stored pair per matching descriptor.
  ;; Keep only the immutable cursors and callback live across this hot loop.
  (def (visit-point-plan-intersection left right point)
    (when (and (pair? left) (pair? right))
      (let ((a (car left)) (b (car right)))
        (using (a :- rectangle-selection)
          (using (b :- rectangle-selection)
            (cond
              ((< a.ordinal b.ordinal)
               (visit-point-plan-intersection (cdr left) right point))
              ((> a.ordinal b.ordinal)
               (visit-point-plan-intersection left (cdr right) point))
              (else
               (point (rectangle-prefix a.block) (car a.members) (car b.members))
               (visit-point-plan-intersection (cdr left) (cdr right) point))))))))
  (def (visit-product-plan-intersection left right bindings consume expand point)
    (when (and (pair? left) (pair? right))
      (let ((a (car left)) (b (car right)))
       (using (a :- rectangle-selection)
        (using (b :- rectangle-selection)
          (cond
            ((< a.ordinal b.ordinal)
             (visit-product-plan-intersection (cdr left) right bindings consume expand point))
            ((> a.ordinal b.ordinal)
             (visit-product-plan-intersection left (cdr right) bindings consume expand point))
            (else
             (when (or (not bindings) (matches-bound-prefix? (rectangle-prefix a.block) bindings 0))
               (if point (point (rectangle-prefix a.block) (car a.members) (car b.members))
                 (expand (rectangle-prefix a.block) a.members b.members consume)))
             (visit-product-plan-intersection (cdr left) (cdr right) bindings consume expand point))))))))
  (def (visit-plan-intersection left right bindings consume expand point)
    (if (and point (not bindings))
      (visit-point-plan-intersection left right point)
      (visit-product-plan-intersection left right bindings consume expand point)))
  (def (visit-bound-plans bindings consume expand)
    (and left-plans bindings
      (let* ((offset (- (vector-length bindings) 2))
             (left (vector-ref bindings offset))
             (right (vector-ref bindings (+ offset 1))))
        ;; A prefix constraint already narrows its descriptor bucket. Preserve
        ;; that route instead of merging all unrelated endpoint owners.
        (and left right
          (let unbound ((coordinate 0))
            (or (= coordinate offset)
                (and (not (vector-ref bindings coordinate))
                     (unbound (+ coordinate 1)))))
          (let ((a (hash-get left-plans (car left)))
                (b (hash-get right-plans (car right))))
            (and a b
              (begin (visit-plan-intersection a b bindings consume expand #f) #t)))))))
  ;; A compact layout is a captured schema, not a query-order classification.
  (def (compact-query? columns)
    (and complete-columns (not small?) (<= (vector-length routes) 3)
      (pair? columns) (pair? (cdr columns))))
  ;; Multi-owner plans intentionally omit single-owner keys. A missing plan
  ;; is not an absent endpoint: borrow its exact frozen bucket instead.
  (def (visit-compact-owners left right consume expand point)
    (let* ((offset (- (vector-length routes) 2))
           (a (or (hash-get (vector-ref routes offset) (car left)) []))
           (b (or (hash-get (vector-ref routes (+ offset 1)) (car right)) [])))
      (cond
        ((or (null? a) (null? b)) #t)
        ((or (null? (cdr a)) (null? (cdr b)))
         (for-each (lambda (block)
           (let ((x (captured-owner-member a (rectangle-left block)))
                 (y (captured-owner-member b (rectangle-right block))))
             (when (and x y)
               (if point (point (rectangle-prefix block) (car x) (car y))
                 (expand (rectangle-prefix block) x y consume)))))
           (rectangle-bucket-plain
             (if (and (null? (cdr a))
                      (or (pair? (cdr b))
                          (<= (rectangle-bucket-count (cdar a)) (rectangle-bucket-count (cdar b)))))
               (cdar a) (cdar b))))
         #t)
        (else #f))))
  (def (visit-compact-group-block block group left right consume expand point)
    (using (block :- rectangle)
      (when (equal? (car block.prefix) (car group))
        (let (scalar? (and point left right))
          (defrule (axis binding members coordinate)
            (if binding
              (if scalar? (captured-point-member routes members coordinate (car binding))
                ;; A group has already selected this descriptor. Reuse the
                ;; bounded member probe instead of walking every unrelated
                ;; owner sharing the value. Expansion needs exactly one stored
                ;; representative, so detach only this private singleton spine.
                (let (selected (captured-point-member routes members coordinate (car binding)))
                  (and selected (list (car selected)))))
              members))
          (let ((a (axis left block.left 1)) (b (axis right block.right 2)))
            (when (and a b)
              (if scalar? (point block.prefix (car a) (car b))
                (expand block.prefix a b consume))))))))
  ;; Normalize first, then choose the narrowest covered descriptor source.
  ;; Selection only mutates local registers: no closure captures this state.
  ;; A frozen bucket/plan stays borrowed, including during nested callbacks.
  (def (visit-compact-group-plan group left right consume expand point)
    (defrule (owner-cost hits)
      (cond ((null? hits) 0)
            ((null? (cdr hits)) (rectangle-bucket-count (cdar hits)))
            (else (foldl (lambda (hit count) (+ count (rectangle-bucket-count (cdr hit)))) 0 hits))))
    (let* ((hits (or (hash-get (vector-ref routes 0) (car group)) []))
           (cost (owner-cost hits))
           (column 0) (binding group)
           (bucket (and (pair? hits) (null? (cdr hits)) (cdar hits)))
           (plan #f))
      (defrule (narrow next coordinate plans)
        (when (and next (> cost 1))
          (let* ((hits (or (hash-get (vector-ref routes coordinate) (car next)) []))
                 (size (owner-cost hits)))
            (when (< size cost)
              (set! cost size) (set! column coordinate) (set! binding next)
              (set! bucket (and (pair? hits) (null? (cdr hits)) (cdar hits)))
              (set! plan (and (not bucket) plans (hash-get plans (car next))))))))
      (narrow left 1 left-plans)
      (narrow right 2 right-plans)
      ;; The static projection keeps both borrowed source representations in
      ;; one publisher without generic per-descriptor argument packing.
      (defrule (publish source project)
        (for-each (lambda (entry)
          (visit-compact-group-block (project entry) group left right consume expand point)) source))
      (defrule (captured-block entry) entry)
      (defrule (planned-block entry)
        (rectangle-selection-block entry))
      (cond
        ((zero? cost) (void))
        (plan (publish plan planned-block))
        (bucket (publish (rectangle-bucket-plain bucket) captured-block))
        (else
         ;; A sparse/non-self axis can have no cached plan. Native routing
         ;; retains ordinal order and covers that single admitted coordinate.
         (publish (routed-rectangles routes blocks
                    (case column ((0) '(0)) ((1) '(1)) (else '(2)))
                    (list (car binding)) #t) captured-block)))
      #t))
  ;; A single captured descriptor is already the smallest possible route.
  ;; Publish it directly, before allocating a traversal closure or costing
  ;; the other axes. The same admission checks still apply to its members.
  (def (visit-compact-group group left right consume expand point)
    (let (hits (hash-get (vector-ref routes 0) (car group)))
      (cond
        ((not hits) #t)
        ((and (null? (cdr hits)) (= (rectangle-bucket-count (cdar hits)) 1))
         (visit-compact-group-block (car (rectangle-bucket-plain (cdar hits)))
           group left right consume expand point)
         #t)
        (else (visit-compact-group-plan group left right consume expand point)))))
  (def (visit-compact-bindings group left right consume expand point)
    ;; Complete endpoint bindings already select singleton stored values.
    ;; The parts consumer accepts scalars directly: do not re-enter both
    ;; Cartesian axis walkers for every matching frozen descriptor.
    (let (publish-point (or point (and left right (eq? expand visit-left-members) consume)))
      (cond
        ((and (= (vector-length routes) 3) group)
         (visit-compact-group group left right consume expand publish-point))
        ((and left right left-plans)
         (let ((a (hash-get left-plans (car left)))
               (b (hash-get right-plans (car right))))
           (if (and a b)
             (begin (visit-plan-intersection a b #f consume expand publish-point) #t)
             (visit-compact-owners left right consume expand publish-point))))
        ((and left right) (visit-compact-owners left right consume expand publish-point))
        (else #f))))
  (def (visit-compact-query columns key consume expand)
    (and (compact-query? columns)
      (with-compact-bindings (- (vector-length routes) 2) columns key group left right
        (visit-compact-bindings group left right consume expand #f) #t)))
  ;; All built-in consumers share one invocation-owned selection flow. Uniform
  ;; indexed cuts admit coordinate bindings once; mixed/scan cuts retain their
  ;; checked protocol. Frozen two-axis plans replace wide temporary owner
  ;; indexes when available; tiny cuts need no query initialization.
  (def (visit-products columns key consume admitted? expand)
    ;; A cut without routes cannot use any indexed publisher. Preserve the
    ;; original per-block admission and arguments while bypassing pure route
    ;; probes; do not route an unindexed query through the indexed dispatcher.
    (defrule (scan-blocks visit)
      (for-each (lambda (block) (visit block columns key consume #f expand)) blocks))
    (if (not routes)
      (if admitted?
        (scan-blocks visit-admitted-scan-rectangle-parts)
        (scan-blocks visit-scan-rectangle-parts))
      (unless (or (visit-indexed-axis columns key consume expand)
                  (visit-compact-query columns key consume expand))
        (let* ((compiled? (and routes uniform? (not small?) (pair? columns) (pair? (cdr columns))))
               (bindings (and compiled? (compile-rectangle-bindings (vector-length routes) columns key))))
          (when (or (not compiled?) bindings)
            (unless (visit-bound-plans bindings consume expand)
              (let* ((candidates (if bindings (routed-rectangles routes blocks columns key uniform? bindings)
                                  (selected columns key)))
                     (query (and routes (pair? columns)
                              (or scan-route (make-rectangle-query routes #f bindings
                                (or (null? candidates) (null? (cdr candidates)) (null? (cddr candidates))))))))
              ;; Keep the optional-argument visitor binding lexical. A dynamic
              ;; procedure alias requires generic argument packing on every block.
              (defrule (visit-blocks visit)
                (for-each (lambda (block) (visit block columns key consume query expand)) candidates))
              (if (or admitted? (and routes uniform?))
                (visit-blocks visit-admitted-rectangle-parts)
                (visit-blocks visit-rectangle-parts)))))))))
  (def (visit-selected columns key consume admitted? (expand visit-left-members))
    (unless (visit-complete-key columns key consume)
      (visit-products columns key consume admitted? expand)))
  (def (visit-checked columns key consume)
    (if (and (compact-query? columns) (not (equal? columns complete-columns)))
      (with-compact-bindings (- (vector-length routes) 2) columns key group left right
        (unless (visit-compact-bindings group left right consume visit-left-members #f)
          (visit-products columns key consume #f visit-left-members))
        (void))
      (begin (validate-key! columns key) (visit-selected columns key consume #f))))
  (def (visit-admitted columns key consume)
    (visit-selected columns key consume #t))
  ;; Select member axes through the same index/checked traversal as visitors,
  ;; then expand each admitted product directly into one owned list builder.
  ;; No row callback or intermediate public tuple runs inside the product.
;; BEGIN GENERATED LOOKUP MATERIALIZATION
  (def (materialize-selected columns key)
    (defrule (with-product-collector collect! collect-product body ...)
      (with-list-builder (collect!)
        (def (collect-product prefix lefts rights _consume)
          (match prefix
            ([] (collect-rectangle-product a b lefts rights collect! (list a b)))
            ([g] (collect-rectangle-product a b lefts rights collect! (list g a b)))
            (else (collect-rectangle-product a b lefts rights collect! (append prefix (list a b))))))
        body ...))
    (defrule (materialize compact? group left right)
      (with-product-collector collect! collect-product
        ;; Select the publisher once from the captured schema; no match
        ;; continuation is constructed for each emitted scalar pair.
        (def collect-point
          (and compact?
            (if (= (vector-length routes) 2)
              (lambda (_prefix a b) (collect! (list a b)))
              (lambda (prefix a b) (collect! (list (car prefix) a b))))))
        (unless (and compact? (visit-compact-bindings group left right #f collect-product collect-point))
          (visit-products columns key #f #f collect-product))))
    (cond
      ;; Unindexed materialization uses the checked scanner and the same
      ;; collector directly. No indexed predicate or publisher can apply.
      ((not routes)
       (validate-key! columns key)
       (with-product-collector collect! collect-product
         (for-each (lambda (block)
           (visit-scan-rectangle-parts block columns key #f #f collect-product)) blocks)))
      ((compact-query? columns)
       (with-compact-bindings (- (vector-length routes) 2) columns key group left right
         (if (and group (= (vector-length routes) 3)
                  (not (hash-get (vector-ref routes 0) (car group)))) []
           (materialize #t group left right)) []))
      ((and complete-columns (equal? columns complete-columns))
       (validate-key! columns key)
       (with-list-builder (collect!)
         (visit-admitted-complete-key columns key
           (lambda (prefix left right)
             (match prefix
               ([] (collect! (list left right)))
               ([group] (collect! (list group left right)))
               (else (collect! (append prefix (list left right)))))))))
      (else (validate-key! columns key) (materialize #f #f #f #f))))
;; END GENERATED LOOKUP MATERIALIZATION
  (make-relation-view #f #f 0 'total count units
    (lambda (columns key consume)
      (if (null? columns)
        (begin (validate-key! columns key) (gerbil-ascent-write-rectangles! blocks consume))
        (let (write (rectangle-row-writer (and routes uniform? (vector-length routes)) consume))
          (visit-checked columns key write))))
    (lambda (row)
      (let (width (length row))
        (and (>= width 2)
             (or (not membership-routes) (<= width (vector-length membership-routes)))
             (rectangles-contain?
               (if membership-routes
                 (routed-rectangles membership-routes blocks
                   (if (= width (vector-length membership-routes)) query-columns (take query-columns width)) row uniform?)
                 blocks) row width (and uniform? routes)))))
    (lambda ()
      ;; Only this invocation owns the collector spine. Rectangles and member
      ;; lists stay borrowed; each writer emits a fresh detached tuple.
      (materialize-rectangles blocks))
    (make-rectangle-visitors
      (lambda (columns key consume)
        (visit-checked columns key consume))
      visit-admitted materialize-selected))))
