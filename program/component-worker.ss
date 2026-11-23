;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One assigned SCC owns its transferred root/size vectors, fresh frames,
;;; physical indexes and output membership. Borrowed row roots stay persistent.
(import (only-in "component-plan.ss" positive-component-members positive-component-rules)
        (only-in :std/list/list-builder with-list-builder)
        (only-in :std/struct/rbtree RBTree rbtree-get rbtree-put)
        (only-in :gerbil-ascent/core/relation-view make-relation-view)
        (only-in :gerbil-ascent/core/view-value
                 make-part-visitors make-paged-binary-visitors gerbil-ascent-binary-destination-end)
        (only-in "index.ss" gerbil-ascent-make-row-indexes row-indexes-rows row-indexes-old-rows row-indexes-advance! row-indexes-plan-positive-rules!)
        (only-in :gerbil-ascent/core/positive-plan gerbil-ascent-run-positive-plan! gerbil-ascent-pure-positive-plan?))
(export make-component-snapshot gerbil-ascent-component-snapshot gerbil-ascent-run-positive-component!
        gerbil-ascent-functional-result-view gerbil-ascent-branching-result-view
        gerbil-ascent-replay-branching-frontier)
(defstruct component-snapshot (rows sizes))
(defstruct component-layout (slots members rules originals) final: #t)
(defstruct compact-component-snapshot (rows sizes layout) final: #t)

;; Only the closed binary terminal rule calls this route. Slots below count
;; hold original ordinals. Novelty uses the mixed low digit so equal targets
;; do not send every different origin through the same hash bucket.
(defstruct branching-frontier (source size lane count ranges labels edges overrides) final: #t)

(defrule (pair-code left right)
  (fx+ (fxarithmetic-shift-left left 24) right))
(defrule (pair-left row) (fxarithmetic-shift-right row 24))
(defrule (pair-right row) (fxand row #xffffff))
(defrule (pair-novelty-key left right)
  (pair-code left (fxand (fxwrap+ right (fxwrap* left 331804471)) #xffffff)))
(defrule (child-range start end)
  (fx+ (fxarithmetic-shift-left start 30) end))
(defrule (range-start bounds) (fxarithmetic-shift-right bounds 30))
(defrule (range-end bounds) (fxand bounds #x3fffffff))

(def (make-branching-labels edges checkpoint!)
  ;; Rank bounds the depth even for adversarial insertion order. Compress the
  ;; finished private parent map so later cuts have a single exact lookup.
  (let ((parents (make-hash-table-eqv)) (ranks (make-hash-table-eqv))
        (labels (make-hash-table-eqv)))
    (def (root vertex)
      (let (parent (hash-get parents vertex))
        (if parent (root parent) vertex)))
    (hash-for-each
     (lambda (left targets)
       (for-each
        (lambda (right)
          (checkpoint!)
          (let ((a (root left)) (b (root right)))
            (unless (fx= a b)
              (let ((rank-a (or (hash-get ranks a) 0)) (rank-b (or (hash-get ranks b) 0)))
                (if (fx< rank-a rank-b)
                  (hash-put! parents a b)
                  (begin
                    (hash-put! parents b a)
                    (when (fx= rank-a rank-b) (hash-put! ranks a (fx+ rank-a 1)))))))))
        targets))
     edges)
    (hash-for-each (lambda (left _) (checkpoint!) (hash-put! labels left (root left))) edges)
    (hash-for-each (lambda (vertex _) (checkpoint!) (hash-put! labels vertex (root vertex))) parents)
    labels))

;; Return a view alone on ordinary cuts. A caller that can prove append lineage
;; can retain its immutable child intervals together with the view.
(def (gerbil-ascent-branching-result-view rows size room checkpoint! (capture? #f))
  (and (fixnum? #xffffffffffff) (fixnum? size) (<= 32 size #x3fffffff)
       (let/cc refuse
         (let ((edges (make-hash-table-eqv)) (seen (make-hash-table-eqv))
               (lane (make-u64vector size))
               (ranges (and capture? (fixnum? #xfffffffffffffff) (make-u64vector size))) (count 0)
               (capacity (min room #x3fffffff)))
           (def (record! left right)
             (let (key (pair-novelty-key left right))
               (if (hash-get seen key)
                 #f
                 (begin
                   (when (>= count capacity) (refuse #f))
                   (when (fx= count (u64vector-length lane))
                     (let (grown (make-u64vector (min capacity (* count 2))))
                       (subu64vector-move! lane 0 count grown 0)
                       (when ranges
                         (let (new-ranges (make-u64vector (u64vector-length grown)))
                           (subu64vector-move! ranges 0 count new-ranges 0)
                           (set! ranges new-ranges)))
                       (set! lane grown)))
                   (hash-put! seen key #t)
                   (u64vector-set! lane count (pair-code left right))
                   (set! count (fx+ count 1))
                   #t))))
           (for-each
            (lambda (row)
              (checkpoint!)
              (let ((left (car row)) (right (cadr row)))
                (unless (and (fixnum? left) (fixnum? right)
                             (fx<= 0 left) (fx< left right) (fx< right #x1000000)
                             (record! left right))
                  (refuse #f))))
            rows)
           (unless (fx= count size) (refuse #f))
           ;; Walk backward while prepending to preserve the exact borrowed
           ;; source index bucket order, even on a converging path.
           (let build ((index (fx- size 1)))
             (unless (fx< index 0)
               (checkpoint!)
               (let* ((pair (u64vector-ref lane index))
                      (left (fxarithmetic-shift-right pair 24))
                      (right (fxand pair #xffffff)))
                 (hash-put! edges left (cons right (or (hash-get edges left) [])))
                 (build (fx- index 1)))))
           (let rounds ((start 0) (end size))
             (let prefixes ((index (fx- end 1)))
               (unless (fx< index start)
                 (checkpoint!)
                 (let* ((pair (u64vector-ref lane index))
                        (left (fxarithmetic-shift-right pair 24))
                        (middle (fxand pair #xffffff))
                        (before count))
                   (let suffixes ((targets (or (hash-get edges middle) [])))
                     (unless (null? targets)
                       (checkpoint!)
                       (record! left (car targets))
                       (suffixes (cdr targets))))
                   (when ranges (u64vector-set! ranges index (child-range before count)))
                   (prefixes (fx- index 1)))))
             (if (fx= end count)
               (let (view (make-branching-view lane count))
                 (if ranges
                   (cons view (make-branching-frontier rows size lane count ranges
                                (make-branching-labels edges checkpoint!) edges
                                (RBTree (lambda (a b) (fx- a b)))))
                   view))
               (rounds end count)))))))

(def (gerbil-ascent-replay-branching-frontier rows size room checkpoint! previous)
  (and (branching-frontier? previous)
       (using (prior previous :- branching-frontier)
         (and (= size (+ prior.size 1)) (eq? (cdr rows) prior.source)
              (<= prior.count room)
              (let* ((edge (car rows)) (left (car edge)) (right (cadr edge))
                     (dirty (and (fixnum? left) (hash-get prior.labels left))))
                (and dirty (fixnum? right) (fx< left right)
                     (eqv? dirty (hash-get prior.labels right))
                     (let (targets (or (rbtree-get prior.overrides left)
                                       (hash-get prior.edges left) []))
                       (and (not (memv right targets))
                            (replay-branching-frontier prior rows size room checkpoint!
                              dirty left right
                              (rbtree-put prior.overrides left (cons right targets)))))))))))

(def (replay-branching-frontier (prior :- branching-frontier) rows size room checkpoint!
                                dirty left right overrides)
  (let/cc refuse
    (let* ((capacity (min room #x3fffffff))
           (initial (min capacity (+ prior.count 1)))
           (lane (make-u64vector initial))
           (ranges (make-u64vector initial))
           (ordinals (make-s32vector initial))
           (seen (make-hash-table-eqv))
           (count 0))
      (def (append! row old)
        (when (>= count capacity) (refuse #f))
        (when (fx= count (u64vector-length lane))
          (let* ((next (min capacity (* count 2)))
                 (next-lane (make-u64vector next))
                 (next-ranges (make-u64vector next))
                 (next-ordinals (make-s32vector next)))
            (subu64vector-move! lane 0 count next-lane 0)
            (subu64vector-move! ranges 0 count next-ranges 0)
            (subs32vector-move! ordinals 0 count next-ordinals 0)
            (set! lane next-lane)
            (set! ranges next-ranges)
            (set! ordinals next-ordinals)))
        (u64vector-set! lane count row)
        (s32vector-set! ordinals count old)
        (set! count (fx+ count 1)))
      (def (record! left right)
        (let (key (pair-novelty-key left right))
          (unless (hash-get seen key)
            (hash-put! seen key #t)
            (append! (pair-code left right) -1))))
      (checkpoint!)
      (record! left right)
      (let seeds ((index 0))
        (unless (fx= index prior.size)
          (checkpoint!)
          (let* ((row (u64vector-ref prior.lane index))
                 (origin (pair-left row)))
            (if (eqv? dirty (hash-get prior.labels origin))
              (record! origin (pair-right row))
              (append! row index)))
          (seeds (fx+ index 1))))
      (let rounds ((start 0) (end size))
        (let prefixes ((index (fx- end 1)))
          (unless (fx< index start)
            (checkpoint!)
            (let ((old (s32vector-ref ordinals index)) (before count))
              (if (fx< old 0)
                (let* ((row (u64vector-ref lane index))
                       (origin (pair-left row))
                       (middle (pair-right row))
                       (targets (or (rbtree-get overrides middle) (hash-get prior.edges middle) [])))
                  (for-each (lambda (target) (checkpoint!) (record! origin target)) targets))
                (let ((bounds (u64vector-ref prior.ranges old)) (original prior.lane))
                  (let copy ((child (range-start bounds)))
                    (unless (fx= child (range-end bounds))
                      (checkpoint!)
                      (append! (u64vector-ref original child) child)
                      (copy (fx+ child 1))))))
              (u64vector-set! ranges index (child-range before count)))
            (prefixes (fx- index 1))))
        (if (fx= end count)
          (cons (make-branching-view lane count)
                (make-branching-frontier rows size lane count ranges prior.labels prior.edges overrides))
          (rounds end count))))))

;; Nothing that can grow the lane escapes evaluation. All visitors own their
;; cursor and direct list export owns every returned outer and row pair.
(def (make-branching-view lane count)
  (def (matches? left right columns key)
    (or (null? columns)
        (and (equal? (if (= (car columns) 0) left right) (car key))
             (matches? left right (cdr columns) (cdr key)))))
  (def (visit columns key consume)
    (let scan ((index (fx- count 1)))
      (unless (fx< index 0)
        (let* ((pair (u64vector-ref lane index))
               (left (fxarithmetic-shift-right pair 24))
               (right (fxand pair #xffffff)))
          (when (matches? left right columns key) (consume [] left right)))
        (scan (fx- index 1)))))
  (def (contains? row)
    (and (pair? row) (pair? (cdr row)) (null? (cddr row))
         (let/cc found (visit '(0 1) row (lambda _ (found #t))) #f)))
  (def (export)
    (let collect ((index 0) (rows []))
      (if (fx= index count) rows
        (let (pair (u64vector-ref lane index))
          (collect (fx+ index 1)
            (cons (list (fxarithmetic-shift-right pair 24) (fxand pair #xffffff)) rows))))))
  (make-relation-view #f #f 0 'total count count
    (lambda (columns key consume) (visit columns key (lambda (_ left right) (consume (list left right)))))
    contains? export (make-part-visitors visit visit)))

;;; Cache only immutable local relation addressing. Physical vectors, indexes,
;;; frames and membership remain private to each admitted assignment.
(def +component-layouts+
  (make-hash-table-eq weak-keys: #t lock: (make-mutex 'ascent-component-layouts)))

;;; Only pure descriptors acquire a local relation namespace. Keep compiled
;;; readers, matchers, slot extents and delta ordinals in their admitted order.
;; : (-> PurePositivePlan AtomProjection PurePositivePlan)
(def (project-component-plan plan project)
  (unless (gerbil-ascent-pure-positive-plan? plan)
    (error "ASCENT relation projection requires a pure positive plan"))
  (def (project-header header)
    (let (fresh (vector-copy header))
      (vector-set! fresh 0 (project (vector-ref header 0))) fresh))
  (vector (map project-header (vector-ref plan 0))
          (map project-header (vector-ref plan 1))
          (vector-ref plan 2) (vector-ref plan 3) (vector-ref plan 4)))

;;; The collector gives every referenced relation one dense slot in first-use order.
;;; Descriptor projection preserves body/output order and restores original
;;; descriptors at emission, before coordinator budgets and merge credit.
;; : (-> PositiveComponent ComponentLayout)
(def (compile-component-layout component)
  (let ((positions (make-hash-table-eqv)) (atoms (make-hash-table-eq))
        (originals (make-hash-table-eq)) (members #f) (rules #f))
    (let (slots
          (with-list-builder (collect!)
            (def (slot! index)
              (or (hash-get positions index)
                  (let (local (hash-length positions))
                    (hash-put! positions index local) (collect! index) local)))
            (def (project atom)
              (or (hash-get atoms atom)
                  (let (local (vector-copy atom))
                    (vector-set! local 0 (slot! (vector-ref atom 0)))
                    (hash-put! atoms atom local) (hash-put! originals local atom) local)))
            (set! members (map slot! (positive-component-members component)))
            (set! rules
              (map (lambda (rule)
                     (let* ((plan (project-component-plan (vector-ref rule 0) project))
                            (actions (list->vector (vector-ref plan 1)))
                            (pivots (map (lambda (ordinal)
                                           (let* ((action (vector-ref actions ordinal))
                                                  (atom (vector-ref action 0)))
                                             (cons ordinal (vector-ref atom 0))))
                                         (vector-ref rule 1))))
                       (vector plan pivots))) (positive-component-rules component)))))
      (make-component-layout (list->vector slots) members rules originals))))

;;; Native locked primitive operations protect publication; compilation runs
;;; outside the lock and contains no assignment-owned state.
;; : (-> PositiveComponent ComponentLayout)
(def (component-workspace-layout component)
  (or (hash-get +component-layouts+ component)
      (let (fresh (compile-component-layout component))
        (hash-put! +component-layouts+ component fresh) fresh)))

;;; Ready admission copies only referenced roots and sizes from the owner's cut.
;;; Persistent row spines are borrowed; both compact vector headers are transferred.
;; : (-> PositiveComponent RowsVector Sizes CompactComponentSnapshot)
(def (gerbil-ascent-component-snapshot component rows sizes)
  (using (layout (component-workspace-layout component) :- component-layout)
    (make-compact-component-snapshot
      (vector-map (cut vector-ref rows <>) layout.slots)
      (vector-map (cut vector-ref sizes <>) layout.slots) layout)))

;; gerbil-ascent-run-positive-component!
;; : (-> PositiveComponent ProgramSchema ComponentSnapshot Emit Checkpoint Void)
;; | doc m%
;;     Close one projected SCC. The coordinator transfers fresh root and size
;;     vectors once at ready admission; the worker never reads a live frontier.
;;     Only this SCC's output relations need mutable membership tables. External
;;     inputs remain readable through private indexes without duplicating their
;;     membership. Frames belong to this assignment; emitted rows require owner
;;     merge credit before a successor may use them.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-run-positive-component! component schema snapshot emit! checkpoint!)
;;     ;; => completes the assigned SCC before reporting terminal task completion
;;     ```
;;   %
(def (gerbil-ascent-run-positive-component! component schema snapshot emit! checkpoint!
                                             (source-read #f) (stable-membership? #f))
  (if (compact-component-snapshot? snapshot)
    (run-component-workspace! schema snapshot emit! checkpoint! source-read stable-membership?)
    (let (compact (gerbil-ascent-component-snapshot component (component-snapshot-rows snapshot)
                    (component-snapshot-sizes snapshot)))
      ;; Full transferred snapshots retain their existing committed-output contract.
      ;; Unwind returns only owned output slots; external source roots stay untouched.
      (dynamic-wind void
        (lambda () (run-component-workspace! schema compact emit! checkpoint! #f #f))
        (lambda ()
          (using (layout (compact-component-snapshot-layout compact) :- component-layout)
            (for-each
             (lambda (local)
               (let (global (vector-ref layout.slots local))
                 (vector-set! (component-snapshot-rows snapshot) global
                   (vector-ref (compact-component-snapshot-rows compact) local))
                 (vector-set! (component-snapshot-sizes snapshot) global
                   (vector-ref (compact-component-snapshot-sizes compact) local)))) layout.members)))))))

;;; All mutable vectors and physical indexes use the assignment's dense namespace.
;;; Global descriptors return only through emission; predecessor inputs remain borrowed.
;; : (-> ProgramSchema CompactComponentSnapshot Emit Checkpoint SourceRead Boolean Void)
(def (run-component-workspace! schema (snapshot :- compact-component-snapshot) emit! checkpoint!
                               source-read stable-membership?)
  (using (layout snapshot.layout :- component-layout)
  (let* ((all snapshot.rows)
         (all-size snapshot.sizes)
         (count (vector-length all))
         (delta (make-vector count [])) (delta-size (make-vector count 0))
         (all-version (make-vector count 0)) (delta-version (make-vector count 0))
         (indexes (gerbil-ascent-make-row-indexes all delta all-size delta-size all-version delta-version
                                                  (vector-map (cut vector-ref (vector-ref schema 5) <>) layout.slots)))
         (local-rows (row-indexes-rows indexes))
         (advance! (row-indexes-advance! indexes))
         (seen (make-vector count #f))
         (previously-present? #f)
         (pending (make-vector count []))
         (members layout.members)
         (rules (map (lambda (rule)
                       (vector (vector-ref rule 0) (vector-ref rule 1)
                               (make-vector (vector-ref (vector-ref rule 0) 2) #f)))
                     layout.rules))
         (rows-access
          (if source-read
            (lambda (atom frame delta? terms)
              (or (and (not delta?) (pair? (vector-ref atom 2))
                       (source-read (hash-ref layout.originals atom) frame terms))
                  (local-rows atom frame delta? terms)))
            local-rows)))
    ;; The table callback only records the prior bit. Publish outside the
    ;; update, where the normal checkpoint and merge-credit protocol applies.
    (def (remember-membership present?)
      (set! previously-present? present?)
      #t)
    (row-indexes-plan-positive-rules! indexes rules)
    (for-each
     (lambda (index)
       (let (table (make-hash-table))
         (for-each (lambda (row) (hash-put! table row #t)) (vector-ref all index))
         (vector-set! seen index table))) members)
    (let rounds ((first? #t))
      (let (new? #f)
        (def (candidate! atom row)
          (let* ((index (vector-ref atom 0))
                 (table (vector-ref seen index))
                 (present? (if stable-membership?
                             (begin
                               (hash-update! table row remember-membership #f)
                               previously-present?)
                             (hash-get table row))))
            (unless present?
              (unless stable-membership? (hash-put! table row #t))
              (vector-set! pending index (cons row (vector-ref pending index)))
              (set! new? #t)
              (emit! (hash-ref layout.originals atom) row))))
        (for-each
         (lambda (rule)
           (let ((plan (vector-ref rule 0)) (pivots (vector-ref rule 1)) (frame (vector-ref rule 2)))
             (if first?
               (gerbil-ascent-run-positive-plan! plan frame -1 rows-access candidate! checkpoint!)
               (for-each
                (lambda (pivot)
                  ;; The assignment owns this exact delta count. Empty selected
                  ;; lanes admit no witness, even when their prefix is nonempty.
                  (unless (zero? (vector-ref delta-size (cdr pivot)))
                    (gerbil-ascent-run-positive-plan! plan frame (car pivot) rows-access
                      candidate! checkpoint! #f (row-indexes-old-rows indexes))))
                pivots)))) rules)
        (for-each
         (lambda (index)
           (let* ((batch (vector-ref pending index)) (size (length batch)))
             (unless (null? batch)
               ;; Extend against the old version before publishing new roots.
               ;; Buckets prepend rows; reverse traversal preserves batch order
               ;; exactly as a rebuild over (append batch old) would do.
               (advance! index batch #t)
               (vector-set! all index (append batch (vector-ref all index)))
               (vector-set! all-size index (+ (vector-ref all-size index) size))
               (vector-set! all-version index (+ 1 (vector-ref all-version index))))
             (vector-set! delta index batch)
             ;; The delta owns this persistent batch spine. Reuse only the
             ;; candidate vector header; never clear or mutate the row spine.
             (vector-set! pending index [])
             (vector-set! delta-size index size)
             (vector-set! delta-version index (+ 1 (vector-ref delta-version index))))) members)
        (when new? (rounds #f)))))))

;;; Frozen functional result. Only the admitted terminal Actor path calls it.
(def (ordinal-runs next size direction checkpoint!)
  (and direction (not (fx= direction 0))
       (cons direction
         (list->vector
           (with-list-builder (collect!)
             (collect! 0)
             (let ((shift (if (fx> direction 0) 1 0)))
               (let bounds ((i 1))
                 (unless (fx= i size)
                   (checkpoint!)
                   (when (fx< (##s32vector-ref next (fx- i shift)) 0)
                     (collect! i))
                   (bounds (fx+ i 1)))))
             (collect! size))))))

(def (export-ordinal-runs runs origins targets strides)
  (let* ((direction (car runs)) (bounds (cdr runs))
         (count (fx- (vector-length bounds) 1))
         (active (make-s32vector count)))
    (let initialize ((i 0))
      (unless (fx= i count)
        (s32vector-set! active i i)
        (initialize (fx+ i 1))))
    (let depth ((start 0) (bound count) (step 1) (offset 0) (shift 0) (output []))
      (let gather ((read start) (write start) (output output))
        (if (fx= read bound)
          (if (fx= write start) output
            (depth (fx- write step) (fx- start step) (fx- 0 step)
              (fx+ offset 1) (fx+ shift direction) output))
          (let* ((run (s32vector-ref active read))
                 (lo (vector-ref bounds run))
                 (hi (vector-ref bounds (fx+ run 1)))
                 (from (if (fx< direction 0) (fx+ lo offset) lo))
                 (until (if (fx> direction 0) (fx- hi offset) hi))
                 (output
                  (cond
                   (strides
                    (let* ((first (if (fx> step 0) from (fx- until 1)))
                           (gap (s64vector-ref strides run))
                           (advance (if (fx= direction step) gap (fx- 0 gap))))
                      (let emit ((remaining (fx- until from))
                                 (left (u64vector-ref origins first))
                                 (right (u64vector-ref targets (fx+ first shift)))
                                 (rows output))
                        (if (fx= remaining 0) rows
                          (emit (fx- remaining 1)
                            (fxwrap+ left advance) (fxwrap+ right advance)
                            (cons (list left right) rows))))))
                   ((fx> step 0)
                    (let emit ((i from) (rows output))
                      (if (fx= i until) rows
                        (emit (fx+ i 1)
                          (cons (list (u64vector-ref origins i)
                                      (u64vector-ref targets (fx+ i shift))) rows)))))
                   (else
                    (let emit ((i (fx- until 1)) (rows output))
                      (if (fx< i from) rows
                        (emit (fx- i 1)
                          (cons (list (u64vector-ref origins i)
                                      (u64vector-ref targets (fx+ i shift))) rows))))))))
            (if (fx= (fx- until from) 1)
              (gather (fx+ read step) write output)
              (begin
                (s32vector-set! active write run)
                (gather (fx+ read step) (fx+ write step) output)))))))))

(def (ordinal-visit-depth runs count checkpoint!)
  (let* ((bounds (cdr runs)) (end (vector-length bounds)))
    (let scan ((i 1) (depth 0))
      (if (fx= i end)
        (and (<= (* depth (fx- end 1)) (* 2 count)) depth)
        (let (width (fx- (vector-ref bounds i) (vector-ref bounds (fx- i 1))))
          (checkpoint!)
          (scan (fx+ i 1) (max depth width)))))))

(defrule (with-ordinal-run-window bounds direction offset run forward? (from until) body miss)
  (let* ((lo (vector-ref bounds run))
         (hi (vector-ref bounds (fx+ run 1)))
         (low (if (fx< direction 0) (fx+ lo offset) lo))
         (high (if (fx> direction 0) (fx- hi offset) hi)))
    (if (fx< low high)
      (let ((from (if forward? low (fx- high 1)))
            (until (if forward? high (fx- low 1))))
        body)
      miss)))

(defrule (visit-ordinal-run-windows runs depths (run from until step shift) emit-window)
  (let* ((direction (car runs)) (bounds (cdr runs))
         (count (fx- (vector-length bounds) 1)))
    ;; The public list reverses emission. Deliver the same sequence from
    ;; highest depth down, reversing both cursor directions at each depth.
    (let depth ((offset (fx- depths 1)))
      (unless (fx< offset 0)
        (let* ((forward? (odd? offset))
               (shift (fx* offset direction))
               (step (if forward? 1 -1))
               (start (if forward? 0 (fx- count 1)))
               (end (if forward? count -1)))
          (let visit ((run start))
            (unless (fx= run end)
              (with-ordinal-run-window bounds direction offset run forward? (from until) emit-window (void))
              (visit (fx+ run step)))))
        (depth (fx- offset 1))))))

(defrule (visit-ordinal-run-fields runs depths origins targets (left right) emit-fields)
  (visit-ordinal-run-windows runs depths (_run first last step shift)
    (let emit ((i first))
      (unless (fx= i last)
        (let ((left (u64vector-ref origins i))
              (right (u64vector-ref targets (fx+ i shift))))
          emit-fields)
        (emit (fx+ i step))))))

(def (ordinal-affine-steps runs origins targets)
  (let/cc decline
    (let* ((bounds (cdr runs)) (count (fx- (vector-length bounds) 1))
           (steps (make-s64vector count)))
      (let next-run ((run 0))
        (if (fx= run count) steps
          (let* ((first (vector-ref bounds run))
                 (until (vector-ref bounds (fx+ run 1)))
                 (gap (fx- (##u64vector-ref targets first) (##u64vector-ref origins first))))
            (let confirm ((i (fx+ first 1)))
              (unless (fx= i until)
                (unless (fx= gap (fx- (##u64vector-ref targets i) (##u64vector-ref origins i)))
                  (decline #f))
                (confirm (fx+ i 1))))
            (##s64vector-set! steps run gap)
            (next-run (fx+ run 1))))))))

(def (visit-ordinal-run-fields! runs depths origins targets consume)
  (visit-ordinal-run-fields runs depths origins targets (left right)
    (consume [] left right)))

(def (make-functional-origin-lookup origins size low high checkpoint! reject)
  (let (extent (+ 1 (fx- high low)))
    (if (and (fixnum? extent) (<= extent (* 2 size)))
      (let (slots (make-s32vector extent -1))
        (let fill ((i 0))
          (unless (fx= i size)
            (checkpoint!)
            (let (slot (fx- (##u64vector-ref origins i) low))
              (unless (fx< (##s32vector-ref slots slot) 0) (reject #f))
              (##s32vector-set! slots slot i))
            (fill (fx+ i 1))))
        (lambda (label)
          (and (fx<= low label) (fx<= label high)
               (let (ordinal (##s32vector-ref slots (fx- label low)))
                 (and (fx>= ordinal 0) ordinal)))))
      (let (positions (make-hash-table-eqv))
        (let fill ((i 0))
          (unless (fx= i size)
            (checkpoint!)
            (let (label (u64vector-ref origins i))
              (when (hash-get positions label) (reject #f))
              (hash-put! positions label i))
            (fill (fx+ i 1))))
        (lambda (label) (hash-get positions label))))))

(def (functional-distance-count next size room checkpoint! reject)
  (let ((lengths (make-s32vector size 0))
        (trail (make-s32vector size)))
    (let count ((i 0) (total 0))
      (if (fx= i size) total
        (let* ((distance
                (let follow ((position i) (depth 0))
                  (checkpoint!)
                  (let (known (if (fx< position 0) 0 (s32vector-ref lengths position)))
                    (if (or (fx< position 0) (fx> known 0))
                      (let record ((depth depth) (known known))
                        (if (fx= depth 0) known
                          (let ((top (fx- depth 1)) (distance (fx+ known 1)))
                            (checkpoint!)
                            (s32vector-set! lengths (s32vector-ref trail top) distance)
                            (record top distance))))
                      (begin
                        (s32vector-set! trail depth position)
                        (follow (s32vector-ref next position) (fx+ depth 1)))))))
               (total (+ total distance)))
          (when (> total room) (reject #f))
          (count (fx+ i 1) total))))))

(def (ordinal-run-count bounds room checkpoint! reject)
  (let (end (vector-length bounds))
    (let count ((i 1) (total 0))
      (if (fx= i end) total
        (let* ((width (fx- (vector-ref bounds i) (vector-ref bounds (fx- i 1))))
               (total (+ total (quotient (* width (+ width 1)) 2))))
          (checkpoint!)
          (when (> total room) (reject #f))
          (count (fx+ i 1) total))))))

(def (gerbil-ascent-functional-result-view rows size room checkpoint! (visit-binary #f))
  (and (<= 32 size #x7fffffff)
       (let/cc fallback
         (let ((origins (make-u64vector size)) (targets (make-u64vector size))
               (next (make-s32vector size -1))
               (low #f) (high 0))
           (def (index! i origin target)
             (checkpoint!)
             (unless (and (fixnum? origin) (fx<= 0 origin)
                          (fixnum? target) (fx< origin target))
               (fallback #f))
             (when (or (not low) (fx< origin low)) (set! low origin))
             (when (fx> origin high) (set! high origin))
             (u64vector-set! origins i origin)
             (u64vector-set! targets i target))
           (if visit-binary
             ;; The forward numeric cursor fills the old newest-first ordinals.
             (let (i (fx- size 1))
               (visit-binary
                 (lambda (origin target)
                   (index! i origin target)
                   (set! i (fx- i 1)))))
             (let index ((rest rows) (i 0))
               (unless (null? rest)
                 (index! i (caar rest) (cadar rest))
                 (index (cdr rest) (fx+ i 1)))))
           (let (origin-ordinal
                 (make-functional-origin-lookup origins size low high checkpoint! fallback))
             ;; Classify ordinal steps while storing the same successor vector.
             ;; Mixed and nonadjacent steps keep the ordinary functional path.
             (let* ((direction
                     (let link ((i 0) (direction 0))
                       (if (fx= i size) direction
                         (begin
                           (checkpoint!)
                           (let (target (or (origin-ordinal (##u64vector-ref targets i)) -1))
                             (##s32vector-set! next i target)
                             (link (fx+ i 1)
                               (cond ((or (not direction) (fx< target 0)) direction)
                                     ((fx= direction 0)
                                      (let (step (fx- target i))
                                        (and (or (fx= step 1) (fx= step -1)) step)))
                                     ((fx= target (fx+ i direction)) direction)
                                     (else #f))))))))
                    (runs (ordinal-runs next size direction checkpoint!))
                    (count (if runs
                             (ordinal-run-count (cdr runs) room checkpoint! fallback)
                             (functional-distance-count next size room checkpoint! fallback)))
                    (depths (and runs (ordinal-visit-depth runs count checkpoint!))))
               (make-functional-view origin-ordinal origins targets next size count runs depths
                 (and depths (index-ordinal-terminals runs targets checkpoint!)))))))))

;; An admitted subwindow has two cells per row, with all fields already
;; certified as fixnums. Its final zero to three rows use the same recurrence.
(defrule (fill-affine-binary-window! destination offset finish length advance first-left first-right)
  (let* ((block-end (fx- finish (fx* (fxand length 3) 2)))
         (advance2 (fxwrap+ advance advance))
         (advance3 (fxwrap+ advance2 advance))
         (advance4 (fxwrap+ advance2 advance2)))
    (let blocks ((at offset)
                 (left first-left)
                 (right first-right))
      (if (fx= at block-end)
        (let tail ((at at) (left left) (right right))
          (unless (fx= at finish)
            (##s64vector-set! destination at left)
            (##s64vector-set! destination (fx+ at 1) right)
            (tail (fx+ at 2) (fxwrap+ left advance) (fxwrap+ right advance))))
        (begin
          (##s64vector-set! destination at left)
          (##s64vector-set! destination (fx+ at 1) right)
          (##s64vector-set! destination (fx+ at 2) (fxwrap+ left advance))
          (##s64vector-set! destination (fx+ at 3) (fxwrap+ right advance))
          (##s64vector-set! destination (fx+ at 4) (fxwrap+ left advance2))
          (##s64vector-set! destination (fx+ at 5) (fxwrap+ right advance2))
          (##s64vector-set! destination (fx+ at 6) (fxwrap+ left advance3))
          (##s64vector-set! destination (fx+ at 7) (fxwrap+ right advance3))
          (blocks (fx+ at 8) (fxwrap+ left advance4) (fxwrap+ right advance4)))))))

(defrule (ordinal-terminal-edge bounds direction run)
  (if (fx> direction 0)
    (fx- (vector-ref bounds (fx+ run 1)) 1)
    (vector-ref bounds run)))

(def (index-ordinal-terminals runs targets checkpoint!)
  (let* ((direction (car runs)) (bounds (cdr runs))
         (terminals (make-hash-table-eqv)))
    (let index ((run (fx- (vector-length bounds) 2)))
      (if (fx< run 0) terminals
        (let (label (##u64vector-ref targets (ordinal-terminal-edge bounds direction run)))
          (checkpoint!)
          (hash-update! terminals label (lambda (later) (cons run later)) [])
          (index (fx- run 1)))))))

(def (ordinal-containing-run bounds edge)
  (let search ((lo 0) (hi (fx- (vector-length bounds) 1)))
    (let (mid (fx+ lo (fxquotient (fx- hi lo) 2)))
      (cond ((fx< edge (vector-ref bounds mid)) (search lo mid))
            ((fx>= edge (vector-ref bounds (fx+ mid 1))) (search (fx+ mid 1) hi))
            (else mid)))))

(def (collect-ordinal-target runs depths origins next origin-ordinal terminals target matches?)
  (let* ((direction (car runs)) (bounds (cdr runs)) (forward? (fx> direction 0)))
    (def (stop run)
      (if forward?
        (fx- (vector-ref bounds run) 1)
        (vector-ref bounds (fx+ run 1))))
    (def (single-run edge run)
      (let (end (stop run))
        (let prepend ((i edge) (rows []))
          (if (fx= i end) rows
            (let (origin (##u64vector-ref origins i))
              (prepend (fx- i direction)
                (if (matches? origin target) (cons (list origin target) rows) rows)))))))
    (def (shared-terminal hits)
      (let ((buckets (make-vector depths [])) (used 0))
        (for-each
         (lambda (run)
           (let (end (stop run))
             (let prepend ((i (ordinal-terminal-edge bounds direction run)) (depth 0))
               (if (fx= i end) (set! used (max used depth))
                 (let (origin (##u64vector-ref origins i))
                   (when (matches? origin target)
                     (vector-set! buckets depth
                       (cons (list origin target) (vector-ref buckets depth))))
                   (prepend (fx- i direction) (fx+ depth 1)))))))
         hits)
        ;; Each bucket retains the public order of that depth.
        (with-list-builder (collect!)
          (let depth ((i (fx- used 1)))
            (unless (fx< i 0)
              (let (rows (vector-ref buckets i))
                (for-each collect! (if (odd? i) (reverse! rows) rows)))
              (depth (fx- i 1)))))))
    (let (origin (origin-ordinal target))
      (if origin
        (let (edge (fx- origin direction))
          (if (and (fx>= edge 0) (fx< edge (s32vector-length next))
                   (fx= (##s32vector-ref next edge) origin))
            (single-run edge (ordinal-containing-run bounds edge))
            []))
        (let (hits (or (hash-get terminals target) []))
          (cond ((null? hits) [])
                ((null? (cdr hits))
                 (let (run (car hits))
                   (single-run (ordinal-terminal-edge bounds direction run) run)))
                (else (shared-terminal hits))))))))

(def (make-functional-view origin-ordinal origins targets next size count runs depths terminals)
  ;; Each read advances one edge per live origin. Successor positions compact
  ;; stably in the current direction, then the next delta reverses that order.
  (defrule (gather origin target keep?)
    (let ((active (make-s32vector size)) (ends (make-s32vector size)))
      (let initialize ((i 0))
        (unless (fx= i size)
          (s32vector-set! active i i)
          (s32vector-set! ends i i)
          (initialize (fx+ i 1))))
      (let depth ((start 0) (bound size) (step 1) (output []))
        (let visit ((read start) (write start) (output output))
          (if (fx= read bound)
            (if (fx= write start) output
              (depth (fx- write step) (fx- start step) (fx- 0 step) output))
            (let* ((origin-index (s32vector-ref active read))
                   (end (s32vector-ref ends read)) (extension (s32vector-ref next end))
                   (origin (u64vector-ref origins origin-index))
                   (target (u64vector-ref targets end))
                   (output (if keep? (cons (list origin target) output) output)))
              (if (fx< extension 0)
                (visit (fx+ read step) write output)
                (begin
                  (s32vector-set! active write origin-index)
                  (s32vector-set! ends write extension)
                  (visit (fx+ read step) (fx+ write step) output)))))))))
  (def (affine-window-steps)
    (and depths
         (let (window-limit (* depths (- (vector-length (cdr runs)) 1)))
           (and (< (+ (* 2 size) (* 3 window-limit)) (* 2 count))
                (ordinal-affine-steps runs origins targets)))))
  (def export
    (if runs (lambda () (export-ordinal-runs runs origins targets (affine-window-steps)))
      (lambda () (gather left right #t))))
  (def (collect columns key)
    (def (matches? origin target)
      (andmap (lambda (column value) (equal? (if (= column 0) origin target) value)) columns key))
    (if (null? columns) (export)
      (let* ((column (memv 0 columns))
             (selected (and column (list-ref key (- (length columns) (length column))))))
        (if (and column (fixnum? selected))
          (let visit ((end (origin-ordinal selected)) (output []))
            (if (and end (fx>= end 0))
              (let (target (u64vector-ref targets end))
                (visit (s32vector-ref next end)
                  (if (matches? selected target) (cons (list selected target) output) output)))
              output))
          (if (and depths (not column) (fixnum? (car key)))
            (collect-ordinal-target runs depths origins next origin-ordinal terminals (car key) matches?)
            (gather left right (matches? left right)))))))
  (def (visit-parts columns key consume)
    (if (and depths (null? columns))
      (visit-ordinal-run-fields! runs depths origins targets consume)
      (for-each (lambda (row) (consume [] (car row) (cadr row))) (collect columns key))))
  (def (copy! destination start)
    (let* ((end (gerbil-ascent-binary-destination-end destination start count))
           (offset start)
           (steps (affine-window-steps)))
      (if steps
        (let (direction (car runs))
          (visit-ordinal-run-windows runs depths (run first last step shift)
            (let* ((length (if (fx> step 0) (fx- last first) (fx- first last)))
                   (finish (+ offset (* 2 length)))
                   (gap (s64vector-ref steps run))
                   (advance (if (fx= direction step) gap (fx- 0 gap))))
              (when (> finish end) (error "ASCENT ordered field count exceeded"))
              (fill-affine-binary-window! destination offset finish length advance
                (u64vector-ref origins first) (u64vector-ref targets (fx+ first shift)))
              (set! offset finish))))
        (visit-ordinal-run-fields runs depths origins targets (left right)
          (begin
            (when (fx>= offset end) (error "ASCENT ordered field count exceeded"))
            (##s64vector-set! destination offset left)
            (##s64vector-set! destination (fx+ offset 1) right)
            (set! offset (fx+ offset 2)))))
      (unless (fx= offset end) (error "ASCENT ordered field count incomplete"))))
  (def (stage destination state length)
    (let* ((direction (car runs)) (bounds (cdr runs))
           (last-run (fx- (vector-length bounds) 2)) (end (fx* 2 length))
           (steps (if state (vector-ref state 3) (affine-window-steps))))
      (def (first-run depth) (if (odd? depth) 0 last-run))
      (let depth ((offset (if state (vector-ref state 0) (fx- depths 1))) (write 0) (resume state))
        (when (fx< offset 0) (error "ASCENT ordinal page incomplete"))
        (let* ((forward? (odd? offset)) (step (if forward? 1 -1))
               (past (if forward? (fx+ last-run 1) -1)) (shift (fx* offset direction)))
          (let window ((run (if resume (vector-ref resume 1) (first-run offset)))
                       (at (and resume (vector-ref resume 2))) (write write))
            (if (fx= run past)
              (depth (fx- offset 1) write #f)
              (with-ordinal-run-window bounds direction offset run forward? (from until)
                (let* ((start (or at from))
                       (available (if forward? (fx- until start) (fx- start until)))
                       (rows (min available (fxquotient (fx- end write) 2)))
                       (finish (fx+ write (fx* rows 2)))
                       (next (fx+ start (fx* rows step))))
                  (when (fx> rows 0)
                    (if steps
                      (let* ((gap (##s64vector-ref steps run))
                             (advance (if (fx= direction step) gap (fx- 0 gap))))
                        (fill-affine-binary-window! destination write finish rows advance
                          (##u64vector-ref origins start)
                          (##u64vector-ref targets (fx+ start shift))))
                      (let fill ((i start) (target write))
                        (unless (fx= target finish)
                          (##s64vector-set! destination target (##u64vector-ref origins i))
                          (##s64vector-set! destination (fx+ target 1)
                            (##u64vector-ref targets (fx+ i shift)))
                          (fill (fx+ i step) (fx+ target 2))))))
                  (if (fx= finish end) (vector offset run next steps)
                    (window (fx+ run step) #f finish)))
                (window (fx+ run step) #f write))))))))
  (make-relation-view #f #f 0 'total count count
    (lambda (columns key consume) (for-each consume (collect columns key)))
    (lambda (row) (and (pair? row) (pair? (cdr row)) (null? (cddr row))
                       (pair? (collect '(0 1) row))))
    export (if depths
             (make-paged-binary-visitors visit-parts visit-parts export copy! #f stage)
             (make-part-visitors visit-parts visit-parts))))
