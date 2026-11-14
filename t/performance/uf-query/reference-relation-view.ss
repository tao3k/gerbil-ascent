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
(defstruct rectangle-query (routes axes) final: #t)
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
  (using (query :- rectangle-query)
    (def hits (or (hash-get (vector-ref query.routes coordinate) value) []))
    (cond
      ((null? hits) #f)
      ((null? (cdr hits))
       (and (eq? (rectangle-bucket-members (cdar hits)) members) (caar hits)))
      (else
       (unless query.axes (set! query.axes (make-vector (vector-length query.routes) #f)))
       (let (owners (or (vector-ref query.axes coordinate)
                       (let (table (make-hash-table-eq))
                         (for-each (lambda (hit)
                           (hash-put! table (rectangle-bucket-members (cdr hit)) (car hit))) hits)
                         (vector-set! query.axes coordinate table) table)))
         (hash-get owners members))))))
(def (selected-members members coordinate columns key routes)
  (let find ((remaining columns) (values key))
    (cond ((null? remaining) members)
          ((= (car remaining) coordinate)
           (let (present (if routes (captured-member routes members coordinate (car values))
                                    (member (car values) members)))
             (if (and present (matches-coordinate? (car present) coordinate columns key))
               (if routes present (list (car present))) [])))
          (else (find (cdr remaining) (cdr values))))))
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
(def (visit-rectangle-parts block columns key consume (routes #f) (expand visit-left-members))
  (let (offset (length (rectangle-prefix block)))
    (unless (andmap (lambda (column) (< column (+ offset 2))) columns)
      (error "invalid ASCENT UF view column")))
  (visit-admitted-rectangle-parts block columns key consume routes expand))
(def (visit-admitted-rectangle-parts block columns key consume routes (expand visit-left-members))
  (let* ((prefix (rectangle-prefix block)) (offset (length prefix)))
    (when (andmap (lambda (column value)
                    (or (>= column offset) (equal? (list-ref prefix column) value))) columns key)
      (let ((lefts (selected-members (rectangle-left block) offset columns key routes))
            (rights (selected-members (rectangle-right block) (+ offset 1) columns key routes)))
        (expand prefix lefts rights consume)))))
(def (visit-admitted-blocks blocks columns key consume routes)
  (unless (null? blocks)
    (visit-admitted-rectangle-parts (car blocks) columns key consume routes)
    (visit-admitted-blocks (cdr blocks) columns key consume routes)))
;; Build once from owned spines. Each component contributes its members once
;; per coordinate; the buckets retain descriptor references, never pair tuples.
;; Readers only inspect these private tables after construction.
(def (rectangle-routing blocks)
  (let* ((arity (foldl (lambda (block n) (max n (+ 2 (length (rectangle-prefix block))))) 0 blocks))
         (owners (list->vector (map (lambda (_) (make-hash-table-eq)) (iota arity))))
         (routes (list->vector (map (lambda (_) (make-hash-table)) (iota arity)))))
    (for-each (lambda (block ordinal)
      (let* ((prefix (rectangle-prefix block)) (offset (length prefix)))
        (def (add! column identity members)
          (let* ((table (vector-ref owners column))
                 (bucket (or (hash-get table identity)
                             (let (fresh (make-rectangle-bucket members [] 0 []))
                               (hash-put! table identity fresh) fresh))))
            (rectangle-bucket-blocks-set! bucket
              (cons (cons ordinal block) (rectangle-bucket-blocks bucket)))
            (rectangle-bucket-count-set! bucket (+ 1 (rectangle-bucket-count bucket)))))
        (for-each (lambda (column value) (add! column prefix (list value))) (iota offset) prefix)
        (add! offset (rectangle-left block) (rectangle-left block))
        (add! (+ offset 1) (rectangle-right block) (rectangle-right block)))) blocks (iota (length blocks)))
    (for-each (lambda (column)
      (hash-for-each (lambda (_ bucket)
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
        (vector-ref owners column))) (iota arity))
    routes))
;; Choose the smallest descriptor bucket, then preserve captured traversal order.
;; Other coordinates (including repeated constraints) remain checked by visitor.
(def (routed-rectangles routes blocks columns key (uniform? #f))
  (if (null? columns) blocks
    (let ((selected #f) (cost +inf.0))
      (for-each (lambda (column value)
        (when (>= column (vector-length routes)) (error "invalid ASCENT UF view column"))
        ;; A single descriptor is already minimal for traversal. Remaining
        ;; coordinates still receive range checks here and value checks in
        ;; the visitor, including absent keys and repeated constraints.
        (when (> cost 1)
          (let* ((buckets (or (hash-get (vector-ref routes column) value) []))
                 (size (foldl (lambda (hit n) (+ n (rectangle-bucket-count (cdr hit)))) 0 buckets)))
            (when (< size cost) (set! selected buckets) (set! cost size))))) columns key)
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
    (let ((plans (make-hash-table)) (owners (make-hash-table-eq)))
      (hash-for-each (lambda (value hits)
        (when (pair? (cdr hits))
          (hash-put! plans value [])
          (for-each (lambda (hit)
            (hash-put! owners (rectangle-bucket-members (cdr hit)) (cdr hit))) hits)))
        (vector-ref routes (- (vector-length routes) 1)))
      (for-each (lambda (block ordinal)
        (let* ((members (rectangle-right block)) (bucket (hash-get owners members)))
          (when bucket
            (for-each (lambda (value)
              (let (hits (hash-get plans value))
                (when (and hits (or (null? hits) (not (= (rectangle-selection-ordinal (car hits)) ordinal))))
                  (hash-put! plans value (cons (make-rectangle-selection ordinal block (list value)) hits))))) members)))) blocks (iota (length blocks)))
      (hash-for-each (lambda (value hits) (hash-put! plans value (reverse! hits))) plans)
      plans)))
(def (gerbil-ascent-rectangle-view blocks count units (indexed? #f))
  (let* ((routes (and indexed? (pair? blocks) (rectangle-routing blocks)))
         ;; One or two descriptors are cheaper to scan than route and gather.
         (membership-routes (and routes (pair? (cdr blocks)) (pair? (cddr blocks)) routes))
         (query-columns (and membership-routes (iota (vector-length membership-routes))))
         (uniform? (or (null? blocks)
                       (let (width (length (rectangle-prefix (car blocks))))
                         (andmap (lambda (block) (= width (length (rectangle-prefix block)))) blocks))))
         (right-plans (ordered-right-plans routes blocks uniform?))
         ;; A self-component cut has the same owner axis on both sides.
         ;; Its frozen descriptor plan can serve either endpoint unchanged.
         (left-plans (and right-plans
                          (andmap (lambda (block) (eq? (rectangle-left block) (rectangle-right block))) blocks)
                          right-plans))
         (grouped? (and (pair? blocks) (= (length (rectangle-prefix (car blocks))) 1))))
  (def (selected columns key)
    (if routes (routed-rectangles routes blocks columns key uniform?) blocks))
  (def (validate-key! columns key)
    (unless (and (list? columns) (list? key) (= (length columns) (length key))
                 (andmap (lambda (column) (and (exact-integer? column) (>= column 0))) columns))
      (error "invalid ASCENT UF view key")))
  (def (selection-for columns)
    (and routes (pair? columns) (make-rectangle-query routes #f)))
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
  (def (visit-admitted columns key consume)
    (cond
      ((visit-indexed-axis columns key consume) (void))
      (else
       (let (query (selection-for columns))
         ;; A sole group descriptor admits the leading group constraint.
         (if (and grouped? routes (pair? columns) (= (car columns) 0))
           (let (hits (or (hash-get (vector-ref routes 0) (car key)) []))
             (cond
               ((null? hits) (void))
               ((and (null? (cdr hits)) (= (rectangle-bucket-count (cdar hits)) 1)
                     (= (length (rectangle-prefix (car (rectangle-bucket-plain (cdar hits))))) 1))
                (visit-admitted-rectangle-parts (car (rectangle-bucket-plain (cdar hits)))
                  (cdr columns) (cdr key) consume query))
               (else (visit-admitted-blocks (selected columns key) columns key consume query))))
           (visit-admitted-blocks (selected columns key) columns key consume query))))))
  ;; Select member axes through the same index/checked traversal as visitors,
  ;; then expand each admitted product directly into one owned list builder.
  ;; No row callback or intermediate public tuple runs inside the product.
  (def (materialize-selected columns key)
    (validate-key! columns key)
    (with-list-builder (collect!)
      (def (collect-product prefix lefts rights _consume)
        (match prefix
          ([] (collect-rectangle-product left right lefts rights collect! (list left right)))
          ([group] (collect-rectangle-product left right lefts rights collect! (list group left right)))
          (else (collect-rectangle-product left right lefts rights collect! (append prefix (list left right))))))
      (unless (visit-indexed-axis columns key #f collect-product)
        (let (query (selection-for columns))
          (for-each (lambda (block)
            (visit-rectangle-parts block columns key #f query collect-product))
            (selected columns key))))))
  (make-relation-view #f #f 0 'total count units
    (lambda (columns key consume)
      (validate-key! columns key)
      (if (null? columns)
        (gerbil-ascent-write-rectangles! blocks consume)
        (let (write (rectangle-row-writer (and routes uniform? (vector-length routes)) consume))
          (unless (visit-indexed-axis columns key write)
            (let (query (selection-for columns))
              (for-each (lambda (block) (visit-rectangle-parts block columns key write query))
                (selected columns key)))))))
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
        (validate-key! columns key)
        (if (visit-indexed-axis columns key consume)
          (void)
          (let (query (selection-for columns))
            (for-each (lambda (block) (visit-rectangle-parts block columns key consume query))
                      (selected columns key)))))
      visit-admitted materialize-selected))))
