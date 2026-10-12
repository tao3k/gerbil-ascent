;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Private union-find SCCs and reachability between component roots.
;;; Concrete frontier rows are returned, never retained in this provider.
(import :gerbil-ascent/core/relation-view (only-in :std/vector/extensible make-ExtensibleVector ExtensibleVector-ref
                 ExtensibleVector-set! ExtensibleVector-fill-pointer
                 ExtensibleVector-fill-pointer-set! ExtensibleVector->list))
(export gerbil-ascent-trrel-uf-insert! gerbil-ascent-trrel-uf-freeze
        gerbil-ascent-trrel-uf-state gerbil-ascent-trrel-uf-extension
        gerbil-ascent-trrel-uf-frontier-extension gerbil-ascent-trrel-uf-snapshot
        gerbil-ascent-trrel-uf-view-count gerbil-ascent-trrel-uf-view-for-each
        gerbil-ascent-trrel-uf-view-lookup
        gerbil-ascent-trrel-uf-observation gerbil-ascent-trrel-uf-resource-observation gerbil-ascent-trrel-uf-validate
        gerbil-ascent-trrel-uf-replay-insert! gerbil-ascent-trrel-uf-count-insert!)
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
(def (rebuild-predecessors! group roots)
  (for-each (lambda (n) (set! (uf-node-predecessors n) (make-hash-table-eq))) roots)
  (for-each (lambda (n)
    (reach-for-each (lambda (target _)
      (set! (uf-node-predecessors target) (reach-put! (uf-node-predecessors target) n group))) (uf-node-reach n))) roots))
;; Closure supplies every external edge to/from the surviving winner already.
;; Retire absorbed reverse keys before clearing any component's storage.
;; : (-> UfNode [UfNode] Void)
(def (retire-cycle-predecessors! winner cycle)
  (for-each (lambda (n)
    (unless (eq? n winner)
      (reach-for-each (lambda (target _)
        (reach-remove! (uf-node-predecessors target) n)) (uf-node-reach n)))
    (reach-remove! (uf-node-predecessors winner) n)) cycle))
;; Complete closure already gives the winner every outgoing cycle edge.
;; Keep its owned reach table; only absorbed keys need removal.
;; : (-> UfGroup [UfNode] [UfNode] Void)
(def (merge-cycle! group roots cycle)
  (let* ((winner (foldl (lambda (n best)
                         (if (> (uf-node-size n) (uf-node-size best)) n best))
                       (car cycle) (cdr cycle)))
         (merged (uf-node-members winner))
         (size (uf-node-size winner))
         (retired (cycle-mask group cycle)))
    (when (uf-group-indexed? group)
      (if (= (length cycle) (uf-group-population group))
        ;; Every reverse key belongs to a retiring root. No external owner
        ;; survives to observe it; release the winner's whole backing table.
        (set! (uf-node-predecessors winner) (make-hash-table-eq))
        (unless retired (retire-cycle-predecessors! winner cycle))))
    (for-each (lambda (n)
      (unless (eq? n winner)
        (set! merged (append (uf-node-members n) merged))
        (set! size (+ size (uf-node-size n)))
        (set! (uf-node-parent n) winner)
        (set! (uf-node-members n) [])
        (set! (uf-node-size n) 0)
        (set! (uf-node-reach n) (make-hash-table-eq))
        (set! (uf-node-predecessors n) #f))) cycle)
    (set! (uf-node-members winner) merged)
    (set! (uf-node-size winner) size)
    (set! roots (filter (lambda (n) (not (uf-node-parent n))) roots))
    (set! (uf-group-roots group) roots)
    (set! (uf-group-population group) (length roots))
    (when (null? (cdr roots)) (set! (uf-group-registry group) #f))
    ;; Dense SCCs retire one stable mask from each surviving reverse owner.
    ;; This avoids revisiting every outgoing arc of every absorbed component.
    (when (and retired (uf-group-indexed? group))
      (reach-remove! retired winner)
      (for-each (lambda (n)
        (let (table (uf-node-predecessors n))
          (if (compact-reach? table) (reach-remove-mask! table retired)
            (for-each (lambda (loser) (unless (eq? loser winner) (reach-remove! table loser))) cycle))
          (when (eq? n winner) (reach-remove! table winner)))) roots)
      (compact-reach-put! retired winner))
    ;; Canonical pre-merge keys plus complete closure mean any external
    ;; predecessor of an absorbed root already reaches the winner. Other DAG
    ;; keys need no rewrite. Iterate a stable list, never the changed table.
    (for-each (lambda (n)
      (if (and (eq? n winner)
               (or (null? (cdr roots))
                   (= (reach-length (uf-node-reach n)) (- (length cycle) 1))))
        ;; No external target: release the old backing array as well as keys.
        (set! (uf-node-reach n) (make-hash-table-eq))
        (when (or (eq? n winner) (reach-get (uf-node-reach n) winner))
          (if (and retired (compact-reach? (uf-node-reach n)))
            (begin
              (unless (eq? n winner) (reach-remove! retired winner))
              (reach-remove-mask! (uf-node-reach n) retired)
              (unless (eq? n winner) (compact-reach-put! retired winner)))
            (for-each (lambda (target)
              (when (or (not (eq? target winner)) (eq? n winner))
                (reach-remove! (uf-node-reach n) target))) cycle))))) roots)
    (for-each (lambda (n)
      (set! (uf-node-reach n) (reach-retired (uf-node-reach n)))
      (when (uf-node-predecessors n)
        (set! (uf-node-predecessors n) (reach-retired (uf-node-predecessors n))))) roots)
    (when (uf-group-registry group)
      (for-each (lambda (n) (unless (eq? n winner) (ExtensibleVector-set! (uf-group-registry group) (uf-node-order n) #f))) cycle))))

;; : (forall (a) (-> UfState Row Natural (-> [Rectangle] Natural Natural a) a))
;; : (-> UfState Row Natural FrontierPublisher Publication)
(def (admit-insertion! groups row budget finish (rectangles? #t))
  (let* ((width (length row))
         (_ (unless (memq width '(2 3))
              (error "ASCENT trrel requires two or three columns" row)))
         (group-key (list width (if (= width 3) (car row) #f)))
         (pair (if (= width 3) (cdr row) row))
         (left (car pair)) (right (cadr pair))
         (stored (hash-get groups group-key))
         (group (or stored (make-uf-group (make-hash-table) [] 0 #f 0 #f)))
         (nodes (uf-group-nodes group))
         (left-node (hash-get nodes left)) (right-node (hash-get nodes right))
         (a (if left-node (root left-node) (fresh left (+ 2 (uf-group-next-order group)) (uf-group-indexed? group))))
         (b (if (equal? left right) a (if right-node (root right-node) (fresh right (+ 1 (uf-group-next-order group)) (uf-group-indexed? group)))))
         (admitted? (and left-node right-node (reachable? a b))))
    (if admitted?
      (begin
        (when (< budget 0) (error "ASCENT trrel output fact budget exceeded"))
        (finish [] 0 0))
      (insert-components! groups (make-uf-insertion group-key group row left-node right-node a b) budget finish rectangles?))))

;; : (-> UfState Row Natural FrozenView)
(def (gerbil-ascent-trrel-uf-insert! groups row budget)
  (admit-insertion! groups row budget gerbil-ascent-rectangle-view))

;; gerbil-ascent-trrel-uf-replay-insert!
;; : (-> UfState Row Natural (-> Natural (Maybe RowWriter)) Void)
;; | doc m%
;;     Commit one whole UF injection before selecting its synchronous writer.
;;     Declined output still reconstructs state for later suffix injections.
;;     Replay creates no temporary view, index or retained row buffer.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-trrel-uf-replay-insert! state '(1 2) 4 (lambda (_) displayln))
;;     ;; => emits the same ordered rows as its frozen injection frontier
;;     ```
;;   %
(def (gerbil-ascent-trrel-uf-replay-insert! groups row budget writer)
  (admit-insertion! groups row budget
    (lambda (blocks count _units)
      (let (emit (writer count))
        (when emit (gerbil-ascent-write-rectangles! blocks emit))))))

;; Admission dispatch precedes rectangle planning. This branch alone owns
;; preflight and commit; an existing closure fact never enters the product scan.
;; : (forall (a) (-> UfState UfInsertion Natural (-> [Rectangle] Natural Natural a) Boolean a))
;; : (-> UfState UfInsertion Natural FrontierPublisher Boolean Publication)
(def (insert-components! groups admission budget finish rectangles?)
  (with (((uf-insertion group-key group row left-node right-node a b) admission))
  (let* ((width (car group-key)) (nodes (uf-group-nodes group))
         (pair (if (= width 3) (cdr row) row)) (left (car pair)) (right (cadr pair))
         (new (append (if left-node [] (list a))
                      (if (or right-node (eq? a b)) [] (list b))))
         (roots (append new (uf-group-roots group)))
         (population (+ (uf-group-population group) (length new)))
         (fresh-product? (and (not (eq? a b)) (or (not left-node) (not right-node))))
         (preds (cond ((not left-node) (list a))
                      ((and (not rectangles?) (not (reachable? b a)) (uf-group-indexed? group)
                            (compact-reach? (uf-node-predecessors a)))
                       (make-closure-axis a (uf-node-predecessors a)))
                      ((uf-group-indexed? group)
                       (ordered-neighbors a (uf-node-predecessors a) roots population (not rectangles?)))
                      (else (select-neighbors (lambda (p) (reachable? p a)) roots (not rectangles?)))))
         (succs (cond ((not right-node) (list b))
                      ((and (not rectangles?) (not (reachable? b a)) (compact-reach? (uf-node-reach b)))
                       (make-closure-axis b (uf-node-reach b)))
                      ((uf-group-indexed? group)
                       (ordered-neighbors b (uf-node-reach b) roots population (not rectangles?)))
                      (else (select-neighbors (lambda (s) (reachable? b s)) roots (not rectangles?)))))
         ;; Capture the intersection in root order before adjacency mutation.
         ;; Succ(b) membership is already represented by b's reach table.
         (cycle (and (not (eq? a b)) (reachable? b a)
                     (if rectangles?
                       (filter (lambda (p) (reachable? b p)) preds)
                       (foldl (lambda (p selected)
                         (if (reachable? b p) (cons p selected) selected)) [] preds))))
         ;; A fresh source or sink has no external arc. Every pair on these
         ;; axes is missing; self-injections retain ordinary admission.
         (changes []) (needed (length new)) (added [])
         (target-mask (and (not fresh-product?)
                           (uf-group-indexed? group) (reach-copyable? (uf-node-reach b) b)
                           (reach-copy-with-node (uf-node-reach b) b)))
         (singleton? (= (uf-group-population group) (hash-length nodes)))
         (excess (and target-mask (target-excess target-mask succs singleton?)))
         (target-weight (and target-mask (axis-weight succs singleton?))))
    ;; Count each missing component rectangle before rows or graph mutation.
    (if (and fresh-product? (not rectangles?))
      (set! needed (+ needed
        (* (axis-weight preds singleton?) (axis-weight succs singleton?))))
      (axis-for-each (lambda (p)
        (if target-mask
          (set! needed (+ needed (reach-difference-weight target-mask p excess target-weight)))
          (axis-for-each (lambda (s)
            (when (or fresh-product? (not (reachable? p s)))
              (set! needed (+ needed (* (uf-node-size p) (uf-node-size s))))
              (when (and rectangles? (not target-mask)) (set! changes (cons (cons p s) changes))))) succs))) preds))
    (when (> needed budget) (error "ASCENT trrel output fact budget exceeded"))
    (when rectangles?
    (let (prefix (if (= width 3) (list (car row)) []))
      (for-each (lambda (n)
        (let (members (uf-node-members n))
          (set! added (cons (make-rectangle prefix members members) added)))) new)
      (when target-mask
        (let (blocks (difference-rectangles prefix target-mask preds succs))
          (set! added (if (null? added) blocks (append blocks added)))))
      (for-each (lambda (change)
        (set! added (cons (make-rectangle prefix
                           (uf-node-members (car change))
                           (uf-node-members (cdr change))) added))) changes)))
    ;; No callback occurs between preflight and commit. Budget rejection has
    ;; not installed new nodes, rewritten parents or altered adjacency.
    (unless (null? new)
      (hash-put! groups group-key group)
      (unless left-node (hash-put! nodes left a))
      (unless right-node (hash-put! nodes right b))
      (set! (uf-group-roots group) roots)
      (set! (uf-group-population group) population)
      (set! (uf-group-next-order group) (+ 2 (uf-group-next-order group)))
      (when (uf-group-registry group)
        (let (registry (uf-group-registry group))
          ;; Native fill-pointer growth captures a continuation. Enter it only
          ;; at geometric reserved-span boundaries, not for every admitted birth.
          (when (>= (uf-group-next-order group) (ExtensibleVector-fill-pointer registry))
            (ExtensibleVector-fill-pointer-set! registry
              (arithmetic-shift 1 (integer-length (uf-group-next-order group))) #f 1))
          (for-each (lambda (n) (ExtensibleVector-set! registry (uf-node-order n) n)) new))))
    ;; Keep small components on the cheaper legacy scan. Activate the reverse
    ;; map only after successful preflight, so rejected admission is read-only.
    (unless (uf-group-indexed? group)
      (when (> population 64)
        (set! (uf-group-indexed? group) #t)
        (rebuild-predecessors! group roots)))
    ;; Only a dense admitted fresh axis qualifies for whole-buffer transfer.
    ;; Existing endpoints still require ordinary missing-pair checks. Sparse
    ;; axes preserve their cheaper scalar path and original insertion order.
    (def copied-sources?
      (and fresh-product? (not right-node) (uf-group-indexed? group)
           (reach-copyable? (uf-node-predecessors a) a)))
    (def copied-targets?
      (and fresh-product? (not left-node)
           (reach-copyable? (uf-node-reach b) b)))
    (when copied-sources?
      (set! (uf-node-predecessors b)
        (reach-copy-with-node (uf-node-predecessors a) a)))
    (when copied-targets?
      (set! (uf-node-reach a) (reach-copy-with-node (uf-node-reach b) b)))
    ;; If every root collapses, all changed arcs would immediately disappear.
    ;; Concrete rectangles were emitted above; no external reach key survives.
    (def (commit-arc! p s)
        (unless copied-targets?
          (set! (uf-node-reach p) (reach-put! (uf-node-reach p) s group)))
        (when (and (uf-group-indexed? group) (not copied-sources?))
          (set! (uf-node-predecessors s) (reach-put! (uf-node-predecessors s) p group))))
    (unless (and cycle (= (length cycle) population))
      (if (and rectangles? (not target-mask))
        (for-each (lambda (change) (commit-arc! (car change) (cdr change))) changes)
        ;; Each root pair is unique. Installing its own arc changes no other
        ;; pair's admission test; no changes spine is needed for count consumers.
        ;; Count axes were selected directly in the original writer order.
        ;; SCC selection separately restored its original root order.
        (let ((sources preds) (targets succs))
          ;; A singleton sink needs one writer for the whole source axis,
          ;; rather than a newly captured inner writer for every source root.
          (match targets
            ([target]
             (axis-for-each (lambda (p)
               (when (or fresh-product? (not (reachable? p target)))
                 (commit-arc! p target))) sources))
            (else
             (axis-for-each (lambda (p)
               (if (and target-mask (compact-reach? (uf-node-reach p)))
                 (reach-difference-commit! target-mask p group)
                 (axis-for-each (lambda (s)
                   (when (or fresh-product? (not (reachable? p s)))
                     (commit-arc! p s))) targets))) sources))))))
    ;; A new a->b edge makes precisely Pred(a) intersect Succ(b) cyclic.
    ;; Merge toward the largest component, bounding union parent depth.
    (when cycle
      (merge-cycle! group roots cycle))
    ;; The descriptor accumulator is private; member spines are persistent.
    (let (units (length added)) (finish (reverse! added) needed units)))))
;; Physical structure counts, not whole-engine memory or allocator receipts.
;; : (-> UfState (Vector Natural))
(def (gerbil-ascent-trrel-uf-observation groups)
  (let ((nodes 0) (components 0) (arcs 0))
    (hash-for-each (lambda (_ g)
      (set! nodes (+ nodes (hash-length (uf-group-nodes g))))
      (set! components (+ components (length (uf-group-roots g))))
      (for-each (lambda (n) (set! arcs (+ arcs (reach-length (uf-node-reach n)))))
                (uf-group-roots g))) groups)
    (vector nodes components arcs)))

;; Physical allocation units, not byte sizes or a whole-engine memory estimate.
;; Fields: sparse entries, occupied words, packed arcs, live registry keys,
;; bitmap payload bytes and registry backing-vector slots (including holes).
;; Both forward and reverse adjacency are counted; the registry is counted once.
;; : (-> UfState (Vector Natural))
(def (gerbil-ascent-trrel-uf-resource-observation groups)
  (let ((sparse 0) (chunks 0) (packed 0) (registry 0) (bytes 0) (slots 0))
    (def (account table)
      (when table
        (if (compact-reach? table)
          (begin (let (bits (compact-reach-bits table))
                   (set! bytes (+ bytes (* 4 (##u32vector-length bits))))
                   (let loop ((i 0))
                     (when (< i (##u32vector-length bits))
                       (unless (zero? (##u32vector-ref bits i)) (set! chunks (+ chunks 1)))
                       (loop (+ i 1)))))
                 (set! packed (+ packed (compact-reach-size table))))
          (set! sparse (+ sparse (hash-length table))))))
    (hash-for-each (lambda (_ group)
      (when (uf-group-registry group)
        (set! registry (+ registry (uf-group-population group)))
        (set! slots (+ slots (length (ExtensibleVector->list (uf-group-registry group))))))
      (for-each (lambda (n) (account (uf-node-reach n)) (account (uf-node-predecessors n)))
                (uf-group-roots group))) groups)
    (vector sparse chunks packed registry bytes slots)))

;; Explicit qualification audit, never called on the insertion/query hot path.
;; This checks the concrete representation premises used by the proof layer.
;; gerbil-ascent-trrel-uf-validate
;; : (-> UfState Boolean)
;; | doc m%
;;     Audit private component ownership, canonical parent roots and closure.
;;     Validation observes state without path compression or graph mutation.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-trrel-uf-validate (gerbil-ascent-trrel-uf-state))
;;     ;; => #t
;;     ```
;;   %
(def (gerbil-ascent-trrel-uf-validate groups)
  (def (require! ok message) (unless ok (error message)))
  (def (unique? values same?)
    (match values
      ([] #t)
      ([head . tail] (and (not (ormap (cut same? head <>) tail)) (unique? tail same?)))))
  (def (checked-root node (seen []))
    (require! (not (memq node seen)) "ASCENT UF parent cycle")
    (match (uf-node-parent node)
      (#f node)
      (parent (checked-root parent (cons node seen)))))
  (hash-for-each (lambda (_ group)
    (let ((nodes (uf-group-nodes group)) (roots (uf-group-roots group)))
      (require! (= (uf-group-population group) (length roots)) "ASCENT UF root population mismatch")
      (when (uf-group-registry group)
        (require! (= (length (filter identity (ExtensibleVector->list (uf-group-registry group)))) (length roots)) "ASCENT UF registry population mismatch")
        (for-each (lambda (n)
          (require! (eq? n (ExtensibleVector-ref (uf-group-registry group) (uf-node-order n))) "ASCENT UF registry owner mismatch")) roots))
      (require! (unique? roots eq?)
                "ASCENT UF duplicate root")
      (let loop ((remaining roots) (ceiling (+ 1 (uf-group-next-order group))))
        (unless (null? remaining)
          (let (order (uf-node-order (car remaining)))
            (require! (and (exact-integer? order) (> order 0) (< order ceiling))
                      "ASCENT UF root scan order mismatch")
            (loop (cdr remaining) order))))
      (hash-for-each (lambda (value node)
        (let (owner (checked-root node))
          (require! (memq owner roots) "ASCENT UF missing root")
          (require! (member value (uf-node-members owner)) "ASCENT UF missing member")
          (when (uf-node-parent node)
            (require! (and (null? (uf-node-members node)) (= (uf-node-size node) 0)
                           (= (reach-length (uf-node-reach node)) 0)
                           (not (uf-node-predecessors node)))
                      "ASCENT UF absorbed storage retained")))) nodes)
      (for-each (lambda (n)
        (let (members (uf-node-members n))
          (require! (not (uf-node-parent n)) "ASCENT UF non-root owner")
          (require! (and (> (uf-node-size n) 0) (= (uf-node-size n) (length members))
                         (unique? members equal?))
                    "ASCENT UF member size mismatch")
          (for-each (lambda (value)
            (let (node (hash-get nodes value))
              (require! (and node (eq? (checked-root node) n)) "ASCENT UF wrong member owner"))) members))
        (for-each (lambda (table)
          (when (and table (compact-reach? table))
            (require! (eq? (compact-reach-registry table) (uf-group-registry group)) "ASCENT UF wrong bit registry")
            (let (degree 0)
              (reach-for-each (lambda (target _) (require! target "ASCENT UF missing bit owner")
                               (set! degree (+ degree 1))) table)
              (require! (= degree (compact-reach-size table)) "ASCENT UF bit cardinality mismatch"))))
          (list (uf-node-reach n) (uf-node-predecessors n)))
        (if (uf-group-indexed? group)
          (begin
            (require! (or (hash-table? (uf-node-predecessors n)) (compact-reach? (uf-node-predecessors n))) "ASCENT UF missing predecessor map")
            (reach-for-each (lambda (predecessor _)
              (require! (and (not (eq? n predecessor)) (memq predecessor roots)
                             (reach-get (uf-node-reach predecessor) n))
                        "ASCENT UF stale predecessor key")) (uf-node-predecessors n)))
          (require! (not (uf-node-predecessors n)) "ASCENT UF premature predecessor map"))
        (reach-for-each (lambda (target _)
          (when (uf-group-indexed? group)
            (require! (reach-get (uf-node-predecessors target) n) "ASCENT UF missing predecessor key"))
          (require! (and (not (eq? n target)) (memq target roots)) "ASCENT UF stale reach key")
          (reach-for-each (lambda (successor _)
            (require! (reachable? n successor) "ASCENT UF incomplete root closure"))
            (uf-node-reach target))) (uf-node-reach n))) roots))) groups)
  #t)

;; Explicit public frontier export preserves the original kernel API/order.
;; : (-> UfState Rows Rows Row Natural Rows)
(def (gerbil-ascent-trrel-uf-extension groups _all _pending row budget)
  (gerbil-ascent-view-rows (gerbil-ascent-trrel-uf-insert! groups row budget)))
;; Freeze root membership and reach into disjoint component rectangles. No
;; parent link or mutable reach table survives in the published representation.
;; : (-> UfState Boolean FrozenView)
(def (gerbil-ascent-trrel-uf-freeze groups (indexed? #t))
  (let ((blocks []) (count 0) (units 0))
    (hash-for-each (lambda (key group)
      (let* ((roots (uf-group-roots group))
             (span (foldl (lambda (n bound)
                     (let (reach (uf-node-reach n))
                       (if (compact-reach? reach)
                         (max bound (* 32 (##u32vector-length (compact-reach-bits reach)))) bound))) 0 roots))
             ;; Capture-only member references, bounded by existing bitmap span.
             ;; Sparse births beyond that span do not enlarge this array.
             (slots (and (> span 0) (make-vector span #f)))
             (members (make-hash-table-eq))
             (prefix (if (= (car key) 3) (list (cadr key)) [])))
        (for-each (lambda (node)
          ;; Merge replaces member fields with append-created spines and clears
          ;; absorbed records; it never mutates an existing member pair. Like
          ;; EqRel capture, borrow that immutable spine without retaining nodes.
          (let (owned (uf-node-members node))
            (set! units (+ units (uf-node-size node)))
            (let (record (make-frozen-members owned (uf-node-size node)))
              (hash-put! members node record)
              (when (and slots (< (uf-node-order node) span))
                (vector-set! slots (uf-node-order node) record))))) (uf-group-roots group))
        (for-each (lambda (node)
          ;; Capture each source owner once. Counts come from committed SCC
          ;; metadata; no arc rescans a copied member spine for cardinality.
          (using (left (hash-get members node) :- frozen-members)
            (def (capture record)
              (using (right record :- frozen-members)
                (set! count (+ count (* left.count right.count)))
                (set! units (+ units 1))
                (set! blocks (cons (make-rectangle prefix left.rows right.rows) blocks))))
            (capture left)
            (let (reach (uf-node-reach node))
              (if (compact-reach? reach)
                (compact-reach-for-each-id (lambda (id) (capture (vector-ref slots id))) reach)
                (hash-for-each (lambda (target _) (capture (hash-get members target))) reach)))))
          (uf-group-roots group)))) groups)
    (gerbil-ascent-rectangle-view (reverse! blocks) count units indexed?)))

;; The proved Provider API and engine adapter share one frozen carrier/kernel.
(def gerbil-ascent-trrel-uf-frontier-extension gerbil-ascent-trrel-uf-insert!)
(def gerbil-ascent-trrel-uf-snapshot gerbil-ascent-trrel-uf-freeze)
(def gerbil-ascent-trrel-uf-view-count relation-view-count)
;; : (-> FrozenView RowWriter Void)
(def (gerbil-ascent-trrel-uf-view-for-each view consume)
  (gerbil-ascent-for-each-row consume view))
;; : (-> FrozenView Columns Key Rows)
(def (gerbil-ascent-trrel-uf-view-lookup view columns key)
  (unless (and (list? columns) (list? key) (= (length columns) (length key))
               (andmap (lambda (column) (and (exact-integer? column) (>= column 0))) columns))
    (error "invalid ASCENT UF view key"))
  (let (rows [])
    (gerbil-ascent-for-each-row (lambda (row) (set! rows (cons row rows)))
                              (gerbil-ascent-view-select view columns key))
    (reverse rows)))


;; gerbil-ascent-trrel-uf-count-insert!
;; : (-> UfState Row Natural Natural)
;; | doc m%
;;     Admit and commit the same whole injection as the frozen frontier kernel,
;;     returning only its cardinality. No rectangle descriptors or emitted rows
;;     are needed for a fresh engine's callback-free initial source accounting.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-trrel-uf-count-insert! (gerbil-ascent-trrel-uf-state) '(0 1) 8)
;;     ;; => 3
;;     ```
;;   %
(def (gerbil-ascent-trrel-uf-count-insert! groups row budget)
  (admit-insertion! groups row budget (lambda (_blocks count _units) count) #f))
