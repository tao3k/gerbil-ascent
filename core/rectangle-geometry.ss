;;; -*- Gerbil -*-
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Pure selection and traversal over borrowed frozen rectangle coordinates.
(import "view-value.ss" (only-in :std/list/list-builder with-list-builder))
(export
  matches-key?
  ordered-key-offsets
  matches-offset-key?
  compile-explicit-key-match
  matches-prefix?
  gerbil-ascent-explicit-view
  gerbil-ascent-lazy-explicit-view
  gerbil-ascent-view-union
  gerbil-ascent-view-difference
  matches-coordinate?
  captured-member
  captured-owner-member
  captured-point-member
  with-compact-bindings
  compile-rectangle-bindings
  matches-bound-prefix?
  select-members-by-column
  selected-scan-members
  selected-members
  visit-right-members
  visit-left-members
  collect-rectangle-product
  materialize-rectangles
  rectangle-row-writer
  gerbil-ascent-write-rectangles!
  define-checked-rectangle-visitor
  with-admitted-rectangle-parts
  define-admitted-rectangle-visitor
  visit-admitted-scan-rectangle-parts
  visit-scan-rectangle-parts
  visit-admitted-rectangle-parts
  visit-rectangle-parts)

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

;; with-compact-bindings
;; : (-> Offset Columns Key GroupBinding LeftBinding RightBinding AdmittedBranch RejectedBranch Syntax)
;; | doc m%
;;     Bind a finite compact key once and validate every requested coordinate.
;;
;;     # Examples
;;
;;     ```scheme
;;     (with-compact-bindings offset columns key group left right admitted rejected)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
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

;; compile-rectangle-bindings
;; : (-> Natural Columns Key (Maybe Bindings))
;; | doc m%
;;     Validate every coordinate before returning one consistent binding vector.
;;
;;     # Examples
;;
;;     ```scheme
;;     (compile-rectangle-bindings width columns key)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
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
;;; Boundary: Selection reads frozen membership only.
;;; Invariant: The retained result order follows the borrowed axis, never hash enumeration.

;; select-members-by-column
;; : (-> Members Coordinate Columns Key Probe Retain Syntax)
;; | doc m%
;;     Select using the first fixed coordinate while preserving the stored representative.
;;
;;     # Examples
;;
;;     ```scheme
;;     (select-members-by-column members coordinate columns key probe retain)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
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

;; selected-scan-members
;; : (-> Members Coordinate Columns Key Members)
;; | doc m%
;;     Keep scan probes lexical and bind the query arguments once.
;;
;;     # Examples
;;
;;     ```scheme
;;     (selected-scan-members members coordinate columns key)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
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

;; collect-rectangle-product
;; : (-> LeftBinding RightBinding LeftMembers RightMembers Emit TupleExpression Syntax)
;; | doc m%
;;     Traverse each selected product in the original left/right callback order.
;;
;;     # Examples
;;
;;     ```scheme
;;     (collect-rectangle-product left right lefts rights emit tuple)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
(defrule (collect-rectangle-product left right lefts rights emit tuple)
  (let collect-left ((pending lefts))
    (cond
      ((null? pending) (void))
      ((pair? pending)
       (let ((left (car pending)) (tail (cdr pending)))
         (let collect-right ((remaining rights))
           (cond
             ((null? remaining) (collect-left tail))
             ((pair? remaining)
              (let ((right (car remaining)) (rest (cdr remaining)))
                (emit tuple)
                (collect-right rest)))
             (else (error "No clause matching" remaining '([]) '([right . rest])))))))
      (else (error "No clause matching" pending '([]) '([left . tail]))))))

(def (materialize-rectangles blocks)
  (with-list-builder (collect!)
    ;; Keep the STD builder on the export stack, outside a for-each closure.
    (let next ((pending blocks))
      (unless (null? pending)
        (with (((rectangle prefix lefts rights) (car pending)))
          (match prefix
            ([] (collect-rectangle-product left right lefts rights collect! (list left right)))
            ([group] (collect-rectangle-product left right lefts rights collect! (list group left right)))
            (else (collect-rectangle-product left right lefts rights collect!
                    (append prefix (list left right))))))
        (next (cdr pending))))))
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
;;; Boundary: The checked entry validates selection before admitted traversal.
;;; Invariant: Caller expressions are bound once by the generated visitor.

;; define-checked-rectangle-visitor
;; : (-> VisitorName AdmittedVisitor Syntax)
;; | doc m%
;;     Generate one checked entry around its complete admitted traversal.
;;
;;     # Examples
;;
;;     ```scheme
;;     (define-checked-rectangle-visitor checked admitted)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
(defrule (define-checked-rectangle-visitor name admitted)
  (def (name block columns key consume (routes #f) (expand visit-left-members))
    (let (offset (length (rectangle-prefix block)))
      (unless (andmap (lambda (column) (< column (+ offset 2))) columns)
        (error "invalid ASCENT UF view column")))
    (admitted block columns key consume routes expand)))
;;; Boundary: Only the owning index supplies admitted columns and keys.
;;; Invariant: Borrowed rectangle coordinates remain immutable across synchronous callbacks.

;; with-admitted-rectangle-parts
;; : (-> Rectangle Columns Key Consumer Routes Expand RoutedFlag Syntax)
;; | doc m%
;;     Borrow immutable coordinates only within the synchronous parts consumer.
;;
;;     # Examples
;;
;;     ```scheme
;;     (with-admitted-rectangle-parts block columns key consume routes expand #t)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
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
;;; Boundary: Generate scan and routed visitors from the same coordinate protocol.
;;; Invariant: Each invocation owns its query context and preserves callback order.

;; define-admitted-rectangle-visitor
;; : (-> VisitorName RoutedFlag Syntax)
;; | doc m%
;;     Generate scan/routed entry points with the same coordinate protocol.
;;
;;     # Examples
;;
;;     ```scheme
;;     (define-admitted-rectangle-visitor visit #t)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
(defrule (define-admitted-rectangle-visitor name routed?)
  (def (name block columns key consume routes (expand visit-left-members))
    (with-admitted-rectangle-parts block columns key consume routes expand routed?)))
;; Both visitors share the complete expansion syntax. The scan macro also
;; keeps the caller's publisher lexical instead of passing it through optional
;; argument functions. Checks, stored representatives and callback order stay
;; in the same sequence; only routed visitors need runtime procedure values.
(define-admitted-rectangle-visitor visit-admitted-rectangle-parts #t)
;;; Boundary: Scan cuts have no route index to consult.
;;; Invariant: The admitted column/key witness belongs to the current call only.

;; visit-admitted-scan-rectangle-parts
;; : (-> Rectangle Columns Key Consumer Routes Expand Syntax)
;; | doc m%
;;     Use the admitted scan path without constructing a route index.
;;
;;     # Examples
;;
;;     ```scheme
;;     (visit-admitted-scan-rectangle-parts block columns key consume routes expand)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
(defrule (visit-admitted-scan-rectangle-parts block columns key consume routes expand)
  (let ((owner block) (constraints columns) (keys key) (visitor consume)
        (query routes) (emit expand))
    (with-admitted-rectangle-parts owner constraints keys visitor query emit #f)))
(define-checked-rectangle-visitor visit-rectangle-parts visit-admitted-rectangle-parts)
;;; Boundary: Custom scan entry checks its complete coordinate selection.
;;; Invariant: No lookup result is retained across caller callbacks.

;; visit-scan-rectangle-parts
;; : (-> Rectangle Columns Key Consumer Routes Expand Syntax)
;; | doc m%
;;     Validate a custom scan selection before visiting its rectangle parts.
;;
;;     # Examples
;;
;;     ```scheme
;;     (visit-scan-rectangle-parts block columns key consume routes expand)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
(defrule (visit-scan-rectangle-parts block columns key consume routes expand)
  (let ((owner block) (constraints columns) (keys key) (visitor consume) (query routes) (emit expand))
    (let (offset (length (rectangle-prefix owner)))
      (unless (andmap (lambda (column) (< column (+ offset 2))) constraints)
        (error "invalid ASCENT UF view column")))
    (visit-admitted-scan-rectangle-parts owner constraints keys visitor query emit)))
;; Build once from owned spines. Each component contributes its members once
;; per coordinate; the buckets retain descriptor references, never pair tuples.
;; Readers only inspect these private tables after construction.
