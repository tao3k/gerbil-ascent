;;; -*- Gerbil -*-
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Private component identities and sparse/packed reachability operations.
(import :gerbil-ascent/core/relation-view (only-in :std/vector/extensible make-ExtensibleVector ExtensibleVector-ref
                 ExtensibleVector-set! ExtensibleVector-fill-pointer
                 ExtensibleVector-fill-pointer-set! ExtensibleVector->list))
(export
  (struct-out uf-node)
  (struct-out uf-group)
  (struct-out uf-insertion)
  (struct-out frozen-members)
  (struct-out compact-reach)
  (struct-out closure-axis)
  axis-for-each
  axis-weight
  reach-length
  reach-get
  reach-remove!
  compact-reach-for-each-id
  reach-for-each
  reach-keys
  compact-reach-put!
  reach-retired
  reach-copyable?
  reach-copy-with-node
  reach-difference-for-each-word
  word-for-each-node
  target-excess
  reach-difference-weight
  targets-disjoint?
  difference-rectangles
  reach-difference-commit!
  reach-remove-mask!
  cycle-mask
  reach-put!
  gerbil-ascent-trrel-uf-state
  root
  reachable?
  fresh
  select-neighbors
  ordered-neighbors)

(defstruct uf-node (parent members size reach predecessors order))
(defstruct uf-group (nodes roots next-order indexed? population registry))
(defstruct uf-insertion (group-key group row left-node right-node a b) final: #t)
(defstruct frozen-members (rows count) final: #t)
;; Primitive accesses below are confined to private allocated buffers; reads
;; check word bounds and writes establish capacity before mutation.
;; Dense adjacency uses 32-bit words and a group-owned birth registry.
;; Sparse maps retain eq hashing below 32 arcs or above two bytes per arc.
;; No bitmap is indexed by a user value. Historical ID gaps stay sparse.
(defstruct compact-reach (bits registry size) final: #t)
;; Read-only dense fresh axes borrow a stable adjacency during this admission.
;; No journal, published cut or group retains this short-lived traversal owner.
(defstruct closure-axis (node table) final: #t)
;; : (-> (-> UfNode Void) (Union ClosureAxis [UfNode]) Void)
(def (axis-for-each consume axis)
  (if (closure-axis? axis)
    (with (((closure-axis node table) axis))
      (let ((self-order (uf-node-order node)) (pending? #t)
            (registry (compact-reach-registry table)))
        (compact-reach-for-each-id
          (lambda (id)
            (when (and pending? (< self-order id))
              (consume node) (set! pending? #f))
            (consume (ExtensibleVector-ref registry id))) table)
        (when pending? (consume node))))
    (for-each consume axis)))
;; : (-> (Union ClosureAxis [UfNode]) Natural)
(def (axis-weight axis (singleton? #f))
  (if singleton?
    (if (closure-axis? axis) (+ 1 (reach-length (closure-axis-table axis))) (length axis))
  (let (weight 0)
    (axis-for-each (lambda (n) (set! weight (+ weight (uf-node-size n)))) axis)
    weight)))
;; : (-> RootTable Natural)
(def (reach-length table)
  (if (compact-reach? table) (compact-reach-size table) (hash-length table)))
;; : (-> RootTable UfNode Boolean)
;;; Membership is read-only during preflight. Evaluate each operand once and
;;; reject words beyond owned capacity before reading the private bit buffer.

;; reach-get
;; : (-> ReachTable UfNode Membership)
;; | doc m%
;;     Read membership once; reject a packed word beyond owned capacity.
;;
;;     # Examples
;;
;;     ```scheme
;;     (reach-get table node)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
(defrules reach-get ()
  ((_ table-expression node-expression)
   (let ((table table-expression) (node node-expression))
     (if (compact-reach? table)
       (let* ((id (uf-node-order node)) (word (fxarithmetic-shift id -5))
              (bits (compact-reach-bits table)))
         (and (fx< word (##u32vector-length bits))
              (not (fxzero? (fxand (##u32vector-ref bits word)
                                  (fxarithmetic-shift 1 (fxand id 31)))))))
       (hash-get table node)))))
;; : (-> RootTable UfNode Void)
(def (reach-remove! table node)
  (if (compact-reach? table)
    (let* ((id (uf-node-order node)) (word (fxarithmetic-shift id -5))
           (bits (compact-reach-bits table)) (bit (fxarithmetic-shift 1 (fxand id 31))))
      (when (and (fx< word (##u32vector-length bits)) (not (fxzero? (fxand (##u32vector-ref bits word) bit))))
        (##u32vector-set! bits word (fxand (##u32vector-ref bits word) (fxnot bit)))
        (set! (compact-reach-size table) (- (compact-reach-size table) 1))))
    (hash-remove! table node)))
;; : (-> (-> Natural Void) CompactReach Void)

;; compact-reach-for-each-id
;; : (-> IdConsumer CompactReach Void)
;; | doc m%
;;     Visit live birth IDs in ascending word/bit order within owned capacity.
;;
;;     # Examples
;;
;;     ```scheme
;;     (compact-reach-for-each-id consume table)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
(def (compact-reach-for-each-id consume table)
  (let (bits (compact-reach-bits table))
    (let words ((word 0))
      (when (fx< word (##u32vector-length bits))
        (let scan ((mask (##u32vector-ref bits word)))
          (unless (fxzero? mask)
            (consume (fx+ (fxarithmetic-shift word 5) (first-set-bit mask)))
            (scan (fxand mask (fx- mask 1)))))
        (words (fx+ word 1))))))
;; : (-> (-> UfNode Boolean Void) RootTable Void)
(def (reach-for-each consume table)
  (if (compact-reach? table)
    (compact-reach-for-each-id
      (lambda (id) (consume (ExtensibleVector-ref (compact-reach-registry table) id) #t)) table)
    (hash-for-each consume table)))
;; : (-> RootTable [UfNode])
(def (reach-keys table)
  (if (compact-reach? table)
    (let (keys []) (reach-for-each (lambda (n _) (set! keys (cons n keys))) table) keys)
    (hash-keys table)))
;; Caller certifies this arc is missing, including reverse-index construction.
;; : (-> CompactReach UfNode Void)
;;; Commit owns capacity and missing-arc admission before entering this macro.
;;; Its cached degree changes once, without another membership probe.

;; compact-reach-put!
;; : (-> CompactReach UfNode Void)
;; | doc m%
;;     Set one new admitted bit after the caller has established word capacity.
;;
;;     # Examples
;;
;;     ```scheme
;;     (compact-reach-put! table node)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
(defrules compact-reach-put! ()
  ((_ table-expression node-expression)
   (let ((table table-expression) (node node-expression))
     (let* ((id (uf-node-order node)) (word (fxarithmetic-shift id -5))
            (bits (compact-reach-bits table)))
       (##u32vector-set! bits word
         (fxior (##u32vector-ref bits word) (fxarithmetic-shift 1 (fxand id 31))))
       (set! (compact-reach-size table) (+ (compact-reach-size table) 1))))))
;; SCC retirement may leave an oversized bitmap with only a few live arcs.
;; Normalize once after retirement, never on each individual bit removal.
;; : (-> RootTable RootTable)
(def (reach-retired table)
  (if (and (compact-reach? table)
           (> (* 4 (##u32vector-length (compact-reach-bits table)))
              (* 4 (max 32 (compact-reach-size table)))))
    (let (sparse (make-hash-table-eq))
      (reach-for-each (lambda (n _) (hash-put! sparse n #t)) table) sparse)
    table))
;; A fresh endpoint owns no arcs. Its complete new adjacency is the existing
;; opposite endpoint's closure plus that endpoint, already admitted as missing.
;; Borrow no mutable buffer: copy the native words once instead of rebuilding
;; a dense index through repeated sparse insertion, promotion and growth.
;; : (-> RootTable UfNode Boolean)
(def (reach-copyable? table node)
  (and (compact-reach? table)
       (let (required (+ 1 (quotient (uf-node-order node) 32)))
         (or (<= required (##u32vector-length (compact-reach-bits table)))
             (<= (* 4 required) (* 2 (+ 1 (compact-reach-size table))))))))
;; : (-> CompactReach UfNode CompactReach)
(def (reach-copy-with-node table node)
  (let* ((bits (compact-reach-bits table))
         (required (+ 1 (quotient (uf-node-order node) 32)))
         (span (max required (##u32vector-length bits)))
         (copy (make-u32vector span 0))
         (owned (make-compact-reach copy (compact-reach-registry table)
                                    (compact-reach-size table))))
    (subu32vector-move! bits 0 (##u32vector-length bits) copy 0)
    (compact-reach-put! owned node)
    owned))
;; One stable target mask serves both read-only admission and commit. Dense
;; differences exclude the source diagonal, which is implicit in an SCC.
;; The callback owns no mutable adjacency until the whole budget is admitted.

;; reach-difference-for-each-word
;; : (-> WordConsumer CompactReach UfNode Void)
;; | doc m%
;;     Emit fresh target word masks while excluding the source self bit.
;;
;;     # Examples
;;
;;     ```scheme
;;     (reach-difference-for-each-word consume targets source)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
(def (reach-difference-for-each-word consume targets source)
  (let ((wanted (compact-reach-bits targets)) (old (compact-reach-bits (uf-node-reach source)))
        (self (uf-node-order source)))
    (let loop ((word 0))
      (when (fx< word (##u32vector-length wanted))
        (let* ((present (if (fx< word (##u32vector-length old)) (##u32vector-ref old word) 0))
               (missing (fxand (##u32vector-ref wanted word) (fxnot present)))
               (mask (if (fx= word (fxarithmetic-shift self -5))
                       (fxand missing (fxnot (fxarithmetic-shift 1 (fxand self 31)))) missing)))
          (unless (fxzero? mask) (consume word mask)))
        (loop (fx+ word 1))))))

;; word-for-each-node
;; : (-> NodeConsumer WordIndex WordMask BirthRegistry Void)
;; | doc m%
;;     Read registry nodes only for the selected finite bits in one word.
;;
;;     # Examples
;;
;;     ```scheme
;;     (word-for-each-node consume word mask registry)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
(def (word-for-each-node consume word mask registry)
  (let loop ((mask mask))
    (unless (fxzero? mask)
      (consume (ExtensibleVector-ref registry (fx+ (fxarithmetic-shift word 5) (first-set-bit mask))))
      (loop (fxand mask (fx- mask 1))))))
;; Target weights are stable for this admission. Most roots remain singleton
;; even after an SCC merge: count all selected bits, then add only heavy-root
;; excess. Summaries are private and never retained by a published frontier.
(def (target-excess targets succs singleton?)
  (and (not singleton?)
    (let ((words #f) (span (##u32vector-length (compact-reach-bits targets))))
      (axis-for-each (lambda (n)
        (when (> (uf-node-size n) 1)
          (unless words (set! words (make-vector span [])))
          (let* ((id (uf-node-order n)) (word (fxarithmetic-shift id -5))
                 (entry (cons (fxarithmetic-shift 1 (fxand id 31)) (- (uf-node-size n) 1))))
            (vector-set! words word (cons entry (vector-ref words word)))))) succs)
      words)))
(def (reach-difference-weight targets source excess target-weight)
  (if (compact-reach? (uf-node-reach source))
  (let (weight 0)
    (reach-difference-for-each-word
      (lambda (word mask)
        (set! weight (+ weight (bit-count mask)))
        (when excess
          (for-each (lambda (entry)
            (unless (fxzero? (fxand mask (car entry)))
              (set! weight (+ weight (cdr entry))))) (vector-ref excess word))))
      targets source)
    (* (uf-node-size source) weight))
    ;; Sparse sources subtract their few present keys from one stable axis
    ;; mass, avoiding a target scan for every short predecessor tail.
    (let (weight (- target-weight (if (reach-get targets source) (uf-node-size source) 0)))
      (reach-for-each (lambda (target _)
        (when (reach-get targets target)
          (set! weight (- weight (uf-node-size target))))) (uf-node-reach source))
      (* (uf-node-size source) weight))))
;; Dense scalar publication shares the admitted difference traversal. A
;; singleton source may concatenate target member spines without changing row
;; order; a heavy source must keep target rectangles separate. Only freshly
;; allocated descriptor/right spines are reversed, never persistent members.

;; targets-disjoint?
;; : (-> CompactReach UfNode Boolean)
;; | doc m%
;;     Check disjoint fresh target sets without changing parent or reach state.
;;
;;     # Examples
;;
;;     ```scheme
;;     (targets-disjoint? targets source)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
(def (targets-disjoint? targets source)
  (and (not (reach-get targets source))
    (let ((table (uf-node-reach source)) (disjoint? #t))
      (if (compact-reach? table)
        (let ((old (compact-reach-bits table)) (wanted (compact-reach-bits targets)))
          (let loop ((word 0))
            (when (and disjoint? (fx< word (fxmin (##u32vector-length old) (##u32vector-length wanted))))
              (unless (fxzero? (fxand (##u32vector-ref old word) (##u32vector-ref wanted word)))
                (set! disjoint? #f))
              (loop (fx+ word 1)))))
        (reach-for-each (lambda (target _) (when (reach-get targets target) (set! disjoint? #f))) table))
      disjoint?)))
(def (difference-rectangles prefix targets preds succs)
  (let ((blocks []) (registry (compact-reach-registry targets)) (shared-rights #f))
    (def (whole-rights)
      (or shared-rights
        (let (rights [])
          (for-each (lambda (target)
            (for-each (lambda (member) (set! rights (cons member rights))) (uf-node-members target)))
            (reverse succs))
          (set! shared-rights (reverse! rights)) shared-rights)))
    (for-each (lambda (source)
      (let ((single? (= (uf-node-size source) 1)) (rights []))
        (def (capture target)
          (if single?
            (for-each (lambda (member) (set! rights (cons member rights))) (uf-node-members target))
            (set! blocks (cons (make-rectangle prefix (uf-node-members source)
                                             (uf-node-members target)) blocks))))
        (if (and single? (targets-disjoint? targets source))
          ;; A complete identical right axis is constructed once, then shared
          ;; immutably by singleton-source descriptors in this publication.
          (set! blocks (cons (make-rectangle prefix (uf-node-members source) (whole-rights)) blocks))
          (begin
            (if (compact-reach? (uf-node-reach source))
              (reach-difference-for-each-word
                (lambda (word mask) (word-for-each-node capture word mask registry)) targets source)
              (for-each (lambda (target) (unless (reachable? source target) (capture target))) (reverse succs)))
            (when (pair? rights)
              (set! blocks (cons (make-rectangle prefix (uf-node-members source) (reverse! rights)) blocks)))))))
      (reverse preds))
    blocks))
;; The sparse fallback owns promotion/growth. A dense table with sufficient
;; capacity installs each missing word once and updates only the reverse arcs.
(def (reach-difference-commit! targets source group)
  (let* ((table (uf-node-reach source)) (bits (compact-reach-bits table))
         (registry (compact-reach-registry targets)))
    (def (commit-reverse! target)
      (set! (uf-node-predecessors target)
        (reach-put! (uf-node-predecessors target) source group)))
    (let (required (##u32vector-length (compact-reach-bits targets)))
      (when (and (fx< (##u32vector-length bits) required)
                 (<= (* required 4) (* 2 (+ (compact-reach-size table) (compact-reach-size targets)))))
        (let (grown (make-u32vector required 0))
          (subu32vector-move! bits 0 (##u32vector-length bits) grown 0)
          (set! (compact-reach-bits table) grown)
          (set! bits grown))))
    (if (fx>= (##u32vector-length bits) (##u32vector-length (compact-reach-bits targets)))
      (reach-difference-for-each-word
        (lambda (word mask)
          (##u32vector-set! bits word (fxior (##u32vector-ref bits word) mask))
          (set! (compact-reach-size table) (+ (compact-reach-size table) (bit-count mask)))
          (word-for-each-node commit-reverse! word mask registry)) targets source)
      (reach-difference-for-each-word
        (lambda (word mask)
          (word-for-each-node (lambda (target)
            (set! (uf-node-reach source) (reach-put! (uf-node-reach source) target group))
            (set! (uf-node-predecessors target)
              (reach-put! (uf-node-predecessors target) source group))) word mask registry)) targets source))))
;; Remove a certified retirement set wordwise. The mask owns its buffer;
;; surviving adjacency owners retain their separate buffers and exact degree.

;; reach-remove-mask!
;; : (-> CompactReach CompactReach Void)
;; | doc m%
;;     Remove retired bits and charge the exact removed cardinality.
;;
;;     # Examples
;;
;;     ```scheme
;;     (reach-remove-mask! table retired)
;;     ;; => the admitted result described by the contract above
;;     ```
;;   %
(def (reach-remove-mask! table retired)
  (let ((bits (compact-reach-bits table)) (mask (compact-reach-bits retired)))
    (let loop ((word 0))
      (when (fx< word (fxmin (##u32vector-length bits) (##u32vector-length mask)))
        (let* ((old (##u32vector-ref bits word)) (removed (fxand old (##u32vector-ref mask word))))
          (unless (fxzero? removed)
            (##u32vector-set! bits word (fxand old (fxnot removed)))
            (set! (compact-reach-size table) (- (compact-reach-size table) (bit-count removed)))))
        (loop (fx+ word 1))))))
(def (cycle-mask group cycle)
  (and (uf-group-registry group) (>= (length cycle) 32)
       (let* ((maximum (foldl (lambda (n id) (max id (uf-node-order n))) 0 cycle))
              (mask (make-compact-reach (make-u32vector (+ 1 (quotient maximum 32)) 0)
                      (uf-group-registry group) 0)))
         (for-each (cut compact-reach-put! mask <>) cycle) mask)))
;; Geometric growth follows std/vector/extensible's owned-buffer contract.
;; Admission has succeeded before allocation, promotion or registry installation.
;; : (-> RootTable UfNode UfGroup RootTable)
(def (reach-put! table node group)
  (if (compact-reach? table)
    (let* ((bits (compact-reach-bits table)) (required (+ 1 (quotient (uf-node-order node) 32))))
      (cond
        ((<= required (##u32vector-length bits)) (compact-reach-put! table node) table)
        ((<= (* required 4) (* 2 (+ (compact-reach-size table) 1)))
         (let (grown (make-u32vector (max required (* 2 (##u32vector-length bits))) 0))
           (subu32vector-move! bits 0 (##u32vector-length bits) grown 0)
           (set! (compact-reach-bits table) grown)
           (compact-reach-put! table node) table))
        (else
          ;; A remote birth ID never forces an oversized dense allocation.
          (let (sparse (make-hash-table-eq))
            (reach-for-each (lambda (n _) (hash-put! sparse n #t)) table)
            (hash-put! sparse node #t) sparse))))
    (begin
      (hash-put! table node #t)
      (let (degree (hash-length table))
        (if (or (< degree 32) (not (zero? (bitwise-and degree (- degree 1))))) table
          (let (maximum 0)
            (hash-for-each (lambda (n _) (set! maximum (max maximum (uf-node-order n)))) table)
            (let (words (+ 1 (quotient maximum 32)))
              (if (> (* words 4) (* 2 degree)) table
                (let* ((registry (or (uf-group-registry group)
                                    (let (index (make-ExtensibleVector (make-vector (+ 1 (uf-group-next-order group)) #f) (+ 1 (uf-group-next-order group))))
                                      (for-each (lambda (n) (ExtensibleVector-set! index (uf-node-order n) n)) (uf-group-roots group))
                                      (set! (uf-group-registry group) index) index)))
                       (packed (make-compact-reach (make-u32vector words 0) registry 0)))
                  (hash-for-each (lambda (n _) (compact-reach-put! packed n)) table)
                  packed)))))))))
;; : (-> UfState)
(def (gerbil-ascent-trrel-uf-state) (make-hash-table))
;; Preflight reads parent links without compression, preserving rejected state.
;; : (-> UfNode UfNode)
(def (root node)
  (if (uf-node-parent node) (root (uf-node-parent node)) node))
;; : (-> UfNode UfNode Boolean)
(def (reachable? from to)
  (or (eq? from to) (reach-get (uf-node-reach from) to)))
;; : (-> Value Natural Boolean UfNode)
(def (fresh node order indexed?)
  (make-uf-node #f (list node) 1 (make-hash-table-eq)
                (and indexed? (make-hash-table-eq)) order))
;; Match the legacy prepended root scan without touching unrelated components.
;; Sparse adjacency sorts only its keys; dense adjacency filters roots already
;; in writer order. Selection compares a sorting bound with the population.
;; : (-> (-> UfNode Boolean) [UfNode] Boolean [UfNode])
(def (select-neighbors accept roots ascending?)
  ;; Gerbil's filter may share an unchanged suffix. Count writers build their
  ;; private ascending axis directly; never reverse a potentially borrowed spine.
  (if ascending?
    (foldl (lambda (n selected) (if (accept n) (cons n selected) selected)) [] roots)
    (filter accept roots)))
;; : (-> UfNode RootTable [UfNode] Natural ?Boolean [UfNode])
(def (ordered-neighbors node table roots population (ascending? #f))
  (let (degree (reach-length table))
    (cond
      ((zero? degree) (list node))
      ((>= (* degree (integer-length degree)) population)
       (select-neighbors (lambda (n) (or (eq? n node) (reach-get table n))) roots ascending?))
      (else (list-sort (lambda (a b) ((if ascending? < >) (uf-node-order a) (uf-node-order b)))
                      (cons node (reach-keys table)))))))
;; : (-> [UfNode] Void)
