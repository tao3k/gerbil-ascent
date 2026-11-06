;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Private positive-rule execution plans. Plans are immutable and shared;
;;; each engine owns its variable frames, including nested/concurrent solves.
(import (only-in "positive-lowering.ss" gerbil-ascent-positive-plan
                 gerbil-ascent-compile-positive-plan gerbil-ascent-positive-plan-with-outputs
                 gerbil-ascent-pure-positive-plan? match-row! term-value)
        (only-in "ordered-call.ss" dispatch-ordered-call)
        (only-in "positive-certificate.ss" gerbil-ascent-positive-certificate?)
        (only-in "execution-policy.ss" gerbil-ascent-old-lane gerbil-ascent-delta-lane)
        (only-in "relation-view.ss" relation-view? gerbil-ascent-for-each-row
                 gerbil-ascent-row-parts? gerbil-ascent-for-each-row-parts)
        (only-in "expression-plan.ss" gerbil-ascent-compile-frame-call gerbil-ascent-compile-frame-sequence
                 gerbil-ascent-compile-input-guard)
        (only-in "rule-bindings.ss" gerbil-ascent-expression-value gerbil-ascent-head-row gerbil-ascent-call-with-bindings))
(export gerbil-ascent-prepare-rule-activations gerbil-ascent-positive-plan gerbil-ascent-compile-positive-plan gerbil-ascent-run-positive-plan!
        gerbil-ascent-positive-plan-with-outputs gerbil-ascent-pure-positive-plan?
        make-positive-prefix-state make-positive-prefix-cut current-positive-prefix-budget
        positive-prefix-state-used positive-prefix-state-node-count
        gerbil-ascent-index-key gerbil-ascent-index-key/terms
        gerbil-ascent-index-value gerbil-ascent-emit-heads!
        make-positive-plan-cost positive-plan-cost-snapshot positive-plan-cost-visits
        call-with-positive-plan-cost current-positive-plan-cost
        positive-plan-cost-admit! positive-plan-cost-begin! positive-plan-cost-index!)

;;; Diagnostic ownership is one fresh serial solve over canonical pure Set
;;; rules. Never share this mutable collector between engines or revisions.
;;; Prefix observations count repeated successful visits, not avoidable work:
;;; a new suffix can legitimately revisit an unchanged prefix.
(defstruct native-plan-cost (counts prefixes started? visits) final: #t)
(def (make-positive-plan-cost (record-prefixes? #t) (record-visits? #f))
  (make-native-plan-cost (make-vector 30 0)
                        (and record-prefixes? (make-hash-table)) #f (and record-visits? [])))
;;; Diagnostic values are detached on read; no callback observes a live frame.
(def (positive-plan-cost-visits cost)
  (unless (native-plan-cost? cost) (error "invalid native visit snapshot"))
  (def (copy value)
    (cond ((pair? value) (cons (copy (car value)) (copy (cdr value))))
          ((vector? value) (list->vector (map copy (vector->list value))))
          (else value)))
  (alet (visits (native-plan-cost-visits cost)) (map copy (reverse visits))))
(def (positive-plan-cost-begin! cost)
  (when cost
    (when (native-plan-cost-started? cost)
      (error "native plan cost collector already belongs to a solve"))
    (native-plan-cost-started?-set! cost #t)))
(def current-positive-plan-cost (make-parameter #f))
(def (call-with-positive-plan-cost cost thunk)
  (unless (and (native-plan-cost? cost) (procedure? thunk))
    (error "invalid native positive-plan cost collector"))
  (parameterize ((current-positive-plan-cost cost)) (thunk)))
(def (cost-add! cost index (amount 1))
  (when cost
    (let (counts (native-plan-cost-counts cost))
      (vector-set! counts index (+ amount (vector-ref counts index))))))
(def (positive-plan-cost-admit! cost) (cost-add! cost 4))
(def (positive-plan-cost-index! kind (rows []))
  (alet (cost (current-positive-plan-cost))
    (case kind
      ((build) (cost-add! cost 14 (length rows)))
      ((extend) (cost-add! cost 15 (length rows)))
      ((probe) (cost-add! cost 16))
      ((membership) (cost-add! cost 17 (length rows)))
      ((empty-test) (cost-add! cost 18))
      ((empty-key) (cost-add! cost 19))
      ((empty-hit) (cost-add! cost 20))
      ((empty-write) (cost-add! cost 21))
      ((empty-entry) (cost-add! cost 22))
      ((empty-version) (cost-add! cost 23))
      ((empty-store) (cost-add! cost 24))
      (else (error "invalid native index cost event" kind)))))
(def (positive-plan-cost-snapshot cost)
  (unless (native-plan-cost? cost) (error "invalid native cost snapshot"))
  (map (lambda (name index)
         (cons name (if (and (<= 5 index 13) (not (native-plan-cost-prefixes cost)))
                      #f (vector-ref (native-plan-cost-counts cost) index))))
       '(candidate-rows partial-matches complete-witnesses head-proposals
         admitted-rows repeated-prefixes repeated-candidate-visits
         same-plan-prefix-revisits cross-plan-prefix-revisits
         same-plan-candidate-revisits cross-plan-candidate-revisits
         repeated-complete-witnesses same-plan-complete-revisits cross-plan-complete-revisits
         index-build-input-rows index-extend-input-rows physical-index-probes old-membership-input-rows
         empty-cell-tests empty-key-comparisons empty-cell-hits empty-cell-writes empty-cell-entries
         empty-version-comparisons empty-field-stores
         prefix-state-tests prefix-build-input-rows prefix-slot-stores prefix-state-replays prefix-slot-restores)
       '(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29)))
(def (cost-prefix! cost kind index signature rows owner)
  (alet (seen (native-plan-cost-prefixes cost))
    (let* ((key (list kind signature rows))
           (owners (hash-get seen key))
           (repeat (and owners (if (hash-get owners owner) 'same-plan 'cross-plan))))
      ;; Partition repeats by compiled plan identity, not by projected head.
      ;; A first visit from a different plan is a sharing candidate, not proof
      ;; that its suffix or its head/provenance work may be skipped.
      (when owners
        (cost-add! cost index)
        (cost-add! cost (+ (case kind ((partial) 7) ((candidate) 9) ((complete) 12))
                          (if (hash-get owners owner) 0 1))))
      (unless owners
        (set! owners (make-hash-table-eq))
        (hash-put! seen key owners))
      (hash-put! owners owner #t)
      repeat)))

(def (emit-parts-heads! heads frame emit-row! (cost #f))
  (unless (null? heads)
    (let (head (car heads))
      (cost-add! cost 3)
      (emit-row! (vector-ref head 0)
        (if (> (vector-length head) 2) ((vector-ref head 2) frame)
            (map (lambda (term) (term-value term frame)) (vector-ref head 1)))))
    (emit-parts-heads! (cdr heads) frame emit-row! cost)))

;;; The engine supplies row/index access and the authoritative output admission
;;; function. This runner changes binding representation, not fact admission.
;; gerbil-ascent-run-positive-plan!
;;   : (-> PositivePlan Frame Integer RowsAccess EmitRow Void)
;;   | doc m%
;;       Execute one positive traversal using the engine-local reusable frame. The engine supplies index access and output admission.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-run-positive-plan! plan frame -1 rows-access emit-row!)
;;       ;; => void after admitting the matching heads
;;       ```
;;     %
;;; A checked execution DAG is shared by plans inside one engine. Slot numbering
;;; is canonical by first occurrence; each plan is independently revalidated
;;; before its ordered prefix signatures are interned. No source-name equality.
(defstruct prefix-node (id action prior fresh uses) final: #t)
(defstruct prefix-lane (cut reader entries charged) final: #t)
(defstruct positive-prefix-cut (owner versions) final: #t)
(defstruct native-prefix-state (paths nodes lanes cut budget used) final: #t)
(def current-positive-prefix-budget
  (make-parameter 0 (lambda (value)
    (unless (and (exact-integer? value) (>= value 0))
      (error "invalid prefix retention budget" value)) value)))
(def (positive-prefix-state-used state) (native-prefix-state-used state))
(def (positive-prefix-state-node-count state) (vector-length (native-prefix-state-nodes state)))
;;; Intentional raw data record: engine-private native-prefix-state fields hold membership and path lookup tables; they do not implement a public object protocol.
(def (make-positive-prefix-state plans cut budget)
  (unless (and (list? plans) (procedure? cut) (exact-integer? budget) (>= budget 0))
    (error "invalid prefix DAG construction"))
  (let ((paths (make-hash-table-eq)) (interned (make-hash-table)) (nodes []))
    (for-each (lambda (plan)
      (unless (and (gerbil-ascent-pure-positive-plan? plan)
                   (gerbil-ascent-positive-certificate?
                    (map (lambda (head) (vector-ref head 0)) (vector-ref plan 0))
                    (map (lambda (action) (vector 'atom (vector-ref action 0))) (vector-ref plan 1)) plan))
        (error "prefix DAG requires an independently checked positive plan"))
      (let ((parent -1) (prior 0) (depth 0) (path []))
        (for-each (lambda (action)
          (set! depth (+ depth 1))
          (let* ((atom (vector-ref action 0))
                 (fresh (filter-map (lambda (term) (and (eq? (car term) 'fresh) (cdr term)))
                                   (vector-ref action 1)))
                 (key (list parent (vector-ref atom 0) (vector-ref action 1)
                            (vector-ref atom 2) (vector-ref action 2)))
                 (node (or (hash-get interned key)
                           (let (node (make-prefix-node (length nodes) action prior fresh 0))
                             (hash-put! interned key node) (set! nodes (cons node nodes)) node))))
            (prefix-node-uses-set! node (+ (prefix-node-uses node) (- (vector-ref plan 4) depth)))
            (set! prior (+ prior (length fresh)))
            (set! parent (prefix-node-id node)) (set! path (cons node path)))) (vector-ref plan 1))
        (hash-put! paths plan (list->vector (reverse path))))) plans)
    (let (ordered (list->vector (reverse nodes)))
      (make-native-prefix-state paths ordered
        (vector-map (lambda (_) (make-prefix-lane #f #f (make-hash-table) 0)) ordered)
        cut budget 0))))
;;; Logical retention units, not allocator bytes: an entry charges six fixed
;;; fields plus every incoming slot; each row charges its row reference, spine
;;; cell and newly written slots. Borrowed immutable scalar values are not copied.
(def (prefix-reserve! state lane units)
  (and (<= (+ (native-prefix-state-used state) units) (native-prefix-state-budget state))
       (begin (native-prefix-state-used-set! state (+ (native-prefix-state-used state) units))
              (prefix-lane-charged-set! lane (+ (prefix-lane-charged lane) units)) #t)))
(def (prefix-release! state lane units)
  (native-prefix-state-used-set! state (- (native-prefix-state-used state) units))
  (prefix-lane-charged-set! lane (- (prefix-lane-charged lane) units)))
(def (prefix-node-for state plan depth)
  (and state (> (native-prefix-state-budget state) 0)
       (vector-ref (hash-get (native-prefix-state-paths state) plan) depth)))

(def (gerbil-ascent-run-positive-plan! plan frame delta-at rows-access emit-row! (checkpoint! #f) (parts-access #f) (old-rows-access #f) (scope #f) (prefix-state #f))
  (when prefix-state
    (unless (and (native-prefix-state? prefix-state)
                 (hash-get (native-prefix-state-paths prefix-state) plan) (not checkpoint!))
      (error "prefix state requires its owning plan and an uninterrupted traversal")))
  ;; The compiled extent covers every read/write, including failed candidates.
  ;; Reject an invalid caller frame before lookup, callbacks or partial writes.
  (unless (and (vector? frame) (>= (vector-length frame) (vector-ref plan 2)))
    (error "ASCENT positive plan frame is smaller than compiled extent"))
  ;; Delta ordinals count relation atoms, not callback segments. An invalid
  ;; selector must not silently become a total traversal or invoke host code.
  (unless (and (exact-integer? delta-at)
               (or (= delta-at -1)
                   (and (<= 0 delta-at) (< delta-at (vector-ref plan 4)))))
    (error "ASCENT positive plan delta selector outside compiled atom extent"))
  ;; Decode Option<Nat> once for the entire traversal, not at every join
  ;; continuation. Generated policies retain primitive hot loops.
  (let ((has-pivot? (>= delta-at 0)) (cost (current-positive-plan-cost)))
    (when (and cost (not (gerbil-ascent-pure-positive-plan? plan)))
      (error "native plan cost requires a pure positive plan"))
    (visit-positive-atoms! (vector-ref plan 1) (vector-ref plan 0)
                          frame (if has-pivot? delta-at 0) has-pivot?
                          0 rows-access emit-row! checkpoint! parts-access old-rows-access
                          cost [] [] (and cost plan) scope prefix-state plan)))

(def (emit-complete-heads! heads frame emit-row! cost signature witness owner)
  (when cost (cost-prefix! cost 'complete 11 signature witness owner))
  (cost-add! cost 2)
  (emit-parts-heads! heads frame emit-row! cost))

;;; PartsAccess is private exact canonical selection, synchronous and complete.
;;; A false return must invoke no consumer; custom/overselecting providers use RowsAccess.
;;; Explicit rows keep the direct list loop; frozen views invoke a local visitor.
;; : (-> Atoms Heads Frame Integer Nat RowsAccess EmitRow Void)
(def (visit-positive-atoms! atoms heads frame pivot has-pivot? depth rows-access emit-row! checkpoint! parts-access old-rows-access cost signature witness owner scope prefix-state plan)
  ;; Syntax owns the candidate protocol; no continuation closure per row.
  ;; Observe the remaining action tail after user code, at the original boundary.
  (defrule (resume next-depth next-signature next-witness)
    (visit-positive-atoms! (cdr atoms) heads frame pivot has-pivot? next-depth
                          rows-access emit-row! checkpoint! parts-access old-rows-access
                          cost next-signature next-witness owner scope prefix-state plan))
  (defrule (accept matched? row action reused?)
    (let ((matched matched?) (next-signature signature) (next-witness witness))
      (unless reused? (cost-add! cost 0))
      (when cost
        ;; Slot identities alpha-normalize variables by first occurrence.
        ;; Include full supporting rows, not stale suffix frame contents.
        (set! next-signature
          (cons (list (vector-ref (vector-ref action 0) 0)
                      (vector-ref action 1)) signature))
        (set! next-witness (cons row witness))
        (unless reused?
        (let (repeat (cost-prefix! cost 'candidate 6 next-signature next-witness owner))
          (when (native-plan-cost-visits cost)
            (native-plan-cost-visits-set! cost
              (cons (list scope (if has-pivot? pivot -1) depth (and matched #t)
                          (if (native-plan-cost-prefixes cost) repeat 'unrecorded)
                          (reverse next-witness)) (native-plan-cost-visits cost))))))
        (when (and matched (not reused?))
          (cost-add! cost 1)
          (cost-prefix! cost 'partial 5 next-signature next-witness owner)))
      (when checkpoint! (checkpoint!))
      (when matched
        (if (null? (cdr atoms))
          (emit-complete-heads! heads frame emit-row! cost next-signature next-witness owner)
          (resume (+ depth 1) next-signature next-witness)))))
  (match atoms
    ([] (emit-complete-heads! heads frame emit-row! cost signature witness owner))
    ([action . _]
     (case (vector-ref action 0)
       ((callbacks) (when ((vector-ref action 1) frame) (resume depth signature witness)))
       (else
        (let* ((delta? (gerbil-ascent-delta-lane depth pivot has-pivot?))
               (old? (gerbil-ascent-old-lane depth pivot has-pivot? (and old-rows-access #t))))
        (let (node (and old? (prefix-node-for prefix-state plan depth)))
        (if (and node (> (prefix-node-uses node) 1))
          (let* ((lane (vector-ref (native-prefix-state-lanes prefix-state) (prefix-node-id node)))
                 (cut ((native-prefix-state-cut prefix-state) (vector-ref (vector-ref action 0) 0)))
                 (slots (prefix-node-fresh node))
                 (key (map (lambda (slot) (vector-ref frame slot)) (iota (prefix-node-prior node)))))
            (cost-add! cost 25)
            (unless (and (positive-prefix-cut? cut)
                         (pair? (positive-prefix-cut-versions cut))
                         (andmap (lambda (n) (and (exact-integer? n) (>= n 0)))
                                 (list (car (positive-prefix-cut-versions cut))
                                       (cdr (positive-prefix-cut-versions cut)))))
              (error "prefix DAG requires an owned index cut"))
            (unless (and (prefix-lane-cut lane)
                         (eq? (positive-prefix-cut-owner cut) (positive-prefix-cut-owner (prefix-lane-cut lane)))
                         (equal? (positive-prefix-cut-versions cut) (positive-prefix-cut-versions (prefix-lane-cut lane)))
                         (eq? old-rows-access (prefix-lane-reader lane)))
              (prefix-release! prefix-state lane (prefix-lane-charged lane))
              (prefix-lane-entries-set! lane (make-hash-table))
              (prefix-lane-cut-set! lane cut) (prefix-lane-reader-set! lane old-rows-access))
            (let (entry (hash-get (prefix-lane-entries lane) key))
              (if entry
                (for-each
                 (lambda (record)
                   (cost-add! cost 28)
                   (for-each (lambda (slot value) (cost-add! cost 29)
                               (vector-set! frame slot value)) slots (cdr record))
                   ;; Incoming support is never cached or substituted. Replay
                   ;; appends this row to each caller's original support spine.
                   (accept #t (car record) action #t)) (cdr entry))
                (let* ((base (+ 6 (length key))) (charged 0) (records [])
                       (retaining? (prefix-reserve! prefix-state lane base)) (published? #f))
                  (when retaining? (set! charged base))
                  (try
                    (begin
                      (for-each
                       (lambda (row)
                         (cost-add! cost 26)
                         (let (matched (match-row! (vector-ref action 1) row frame))
                           (when (and matched retaining?)
                             (let (units (+ 2 (length slots)))
                               (if (prefix-reserve! prefix-state lane units)
                                 (begin (set! charged (+ charged units))
                                   (set! records (cons (cons row (map (lambda (slot)
                                     (cost-add! cost 27) (vector-ref frame slot)) slots)) records)))
                                 (begin (prefix-release! prefix-state lane charged)
                                   (set! charged 0) (set! retaining? #f) (set! records [])))))
                           ;; Streaming never stops at the retention boundary:
                           ;; no restart, lost continuation or query-budget change.
                           (accept matched (and cost row) action #f)))
                       (old-rows-access (vector-ref action 0) frame (vector-ref action 2) #f))
                      (when retaining?
                        (hash-put! (prefix-lane-entries lane) key (cons #t (reverse records)))
                        (set! published? #t)))
                    (finally (unless published?
                               (prefix-release! prefix-state lane charged))))))))
        (unless (and (not old?) parts-access
                  (parts-access (vector-ref action 0) frame delta? (vector-ref action 2)
                    (lambda (prefix left right)
                      (accept ((or (vector-ref action 4) (vector-ref action 3))
                               prefix left right frame)
                              (and cost (append prefix (list left right))) action #f))))
          (let (rows (if old?
                      (old-rows-access (vector-ref action 0) frame (vector-ref action 2) checkpoint!)
                      (rows-access (vector-ref action 0) frame
                                   delta? (vector-ref action 2))))
            (cond
              ((or (pair? rows) (null? rows))
               (let candidates ((remaining rows))
                 (unless (null? remaining)
                   (accept (match-row! (vector-ref action 1) (car remaining) frame)
                           (and cost (car remaining)) action #f)
                   (candidates (cdr remaining)))))
              ((gerbil-ascent-row-parts? rows)
               (gerbil-ascent-for-each-row-parts
                (lambda (prefix left right)
                  (accept ((vector-ref action 3) prefix left right frame)
                          (and cost (append prefix (list left right))) action #f)) rows))
              (else
               (gerbil-ascent-for-each-row
                (lambda (row)
                  (accept (match-row! (vector-ref action 1) row frame)
                          (and cost row) action #f)) rows)))))))))))))

;;; Build the provider's ordered key after index construction. Compiled terms
;;; read proved frame slots; the general path preserves expression callbacks.
;; gerbil-ascent-index-key
;;   : (-> Terms Columns Environment (Maybe SlotTerms) Key)
;;   | doc m%
;;       Build an ordered provider key using compiled slots or the general expression environment. Called after index construction.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-index-key '((literal . 1)) '(0) '() #f)
;;       ;; => '(1)
;;       ```
;;     %
(def (gerbil-ascent-index-key terms columns environment slot-terms)
  (if slot-terms
    (map (lambda (term) (term-value term environment)) slot-terms)
    (map (lambda (column)
           (index-term-value (list-ref terms column) environment))
         columns)))

;;; Prepared atom plans already select terms in physical column order.
;;; Evaluate their values only after index construction, preserving expression
;;; callbacks and the same missing-variable diagnostic as dynamic column keys.
;; : (-> Terms Environment Key)
(def (gerbil-ascent-index-key/terms key-terms environment)
  (map (lambda (term) (index-term-value term environment)) key-terms))

;;; A canonical single-column index consumes the value directly. Keep both
;;; slot frames and general expression/variable environments on their existing
;;; value paths, after index construction and once per candidate lookup.
;; : (-> Term Environment (Maybe SlotTerm) Value)
(def (gerbil-ascent-index-value term environment slot-term)
  (if slot-term (term-value slot-term environment)
      (index-term-value term environment)))

;;; Both key interfaces share value semantics; selection must not evaluate an
;;; expression or retain its result across row candidates or source updates.
;; : (-> Term Environment Value)
(def (index-term-value term environment)
  (case (car term)
    ((literal) (cdr term))
    ((expression) (gerbil-ascent-expression-value (cdr term) environment))
    (else
     (let (bound (assq (cdr term) environment))
       (unless bound (error "unbound ASCENT index variable" (cdr term)))
       (cdr bound)))))

;;; Keep the general interpreter's head order and expression evaluation while
;;; sharing one admission boundary with slot-based positive execution.
;; gerbil-ascent-emit-heads!
;;   : (-> Heads Environment EmitRow Void)
;;   | doc m%
;;       Emit general rule heads in declaration order through the same engine admission function used by positive slot plans.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-emit-heads! '() '() emit-row!)
;;       ;; => void; no heads emitted
;;       ```
;;     %
(def (gerbil-ascent-emit-heads! heads environment emit-row!)
  (let emit ((remaining heads))
    (unless (null? remaining)
      (let (head (car remaining))
        (emit-row! head (gerbil-ascent-head-row (vector-ref head 1) environment)))
      (emit (cdr remaining)))))

;; gerbil-ascent-prepare-rule-activations
;; : (forall (r) (-> (Vector [r]) (Vector [Vector])))
;; : (-> ActiveRulesByStratum ImmutableActivations)
;; | doc m%
;;     Lower immutable activation metadata once with its admitted Analysis.
;;     Prefix vectors and positive plans contain no engine-owned variable frames.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-prepare-rule-activations '#(()))
;;     ;; => '#(())
;;     ```
;;   %
(def (gerbil-ascent-prepare-rule-activations active)
  (vector-map
   (lambda (rules)
     (map (lambda (rule)
            (vector (vector-ref rule 0) (vector-ref rule 1)
                    (vector-ref rule 2) (vector-ref rule 3)
                    (list->vector (active-prefix (vector-ref rule 1)))
                    (gerbil-ascent-positive-plan rule)))
          rules))
   active))

;; active-prefix
;; : (forall (a) (-> [(Vector a)] [Integer]))
;; : (-> CompiledBody [RelationIndex])
;; | doc m%
;;     Only a pure variable-only atom extends the prunable prefix. Computed
;;     bindings retain the evaluator's complete traversal and cannot be skipped.
;;
;;     # Examples
;;
;;     ```scheme
;;     (active-prefix [])
;;     ;; => []
;;     ```
;;   %
(def (active-prefix body)
        (if (and (pair? body) (eq? (vector-ref (car body) 0) 'atom))
          (let (atom (vector-ref (car body) 1))
            (cons (vector-ref atom 0)
                  (if (and (null? (vector-ref atom 2))
                           (andmap (lambda (term)
                                     (eq? (car term) 'variable))
                                   (vector-ref atom 1)))
                    (active-prefix (cdr body)) [])))
          []))
