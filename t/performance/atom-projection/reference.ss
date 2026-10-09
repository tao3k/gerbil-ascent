;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Private positive-rule execution plans. Plans are immutable and shared;
;;; each engine owns its variable frames, including nested/concurrent solves.
(import (only-in :gerbil-ascent/core/relation-view relation-view? gerbil-ascent-for-each-row
                 gerbil-ascent-row-parts? gerbil-ascent-for-each-row-parts)
        (only-in :gerbil-ascent/core/expression-plan gerbil-ascent-compile-frame-call gerbil-ascent-compile-frame-sequence
                 gerbil-ascent-compile-input-guard)
        (only-in :gerbil-ascent/core/rule-bindings gerbil-ascent-expression-value gerbil-ascent-head-row gerbil-ascent-call-with-bindings))
(export gerbil-ascent-prepare-rule-activations gerbil-ascent-positive-plan gerbil-ascent-compile-positive-plan gerbil-ascent-run-positive-plan!
        gerbil-ascent-positive-plan-with-outputs gerbil-ascent-pure-positive-plan?
        gerbil-ascent-index-key gerbil-ascent-index-key/terms
        gerbil-ascent-index-value gerbil-ascent-emit-heads!)

(def +positive-plans+
  (make-hash-table-eq weak-keys: #t lock: (make-mutex 'ascent-positive-plans)))

;;; Compilation runs outside the table's primitive-operation lock. Concurrent
;;; misses may compile equivalent immutable plans, each with engine-local frames.
;;; Cache by immutable admitted active-rule identity, including unsupported
;;; rules. Analysis layout and evaluation-local state remain separate.
;; gerbil-ascent-positive-plan
;;   : (-> ActiveRule (Maybe PositivePlan))
;;   | doc m%
;;       Get an immutable slot plan for one admitted active rule. Unsupported rules return false; cached values never contain a mutable frame.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-positive-plan admitted-rule)
;;       ;; => an immutable plan, or #f for unsupported clauses
;;       ```
;;     %
(def (gerbil-ascent-positive-plan rule)
  (let (entry (hash-get +positive-plans+ rule))
    (if entry
      (cdr entry)
      (let (plan (gerbil-ascent-compile-positive-plan
                  (vector-ref rule 0) (vector-ref rule 1)))
        (hash-put! +positive-plans+ rule (cons #t plan))
        plan))))

;;; Shape belongs to immutable admitted metadata. Ordered columns advance one
;;; cursor; full reverse columns copy in reverse order; other arbitrary or
;;; repeated columns use a temporary positional view. All paths
;;; retain action identity and create a detached selected-list spine.
;; : (-> SlotTerms Columns SlotTerms)
(def (project-slot-terms terms columns)
  (match columns
    ([] [])
    ([column] (list (list-ref terms column)))
    (else
     (def (increasing? remaining prior)
       (or (null? remaining)
           (and (> (car remaining) prior)
                (increasing? (cdr remaining) (car remaining)))))
     (def (reverse-columns? remaining position)
       (if (null? remaining)
         (= position -1)
         (and (= (car remaining) position)
              (reverse-columns? (cdr remaining) (- position 1)))))
     (cond
       ((increasing? columns -1)
        (let select ((remaining terms) (selected columns) (position 0))
          (if (null? selected)
            []
            (let (cursor (list-tail remaining (- (car selected) position)))
              (cons (car cursor)
                    (select (cdr cursor) (cdr selected) (+ (car selected) 1)))))))
       ((and (reverse-columns? columns (car columns))
             (= (+ (car columns) 1) (length terms)))
        (reverse terms))
       (else
        (let (positions (list->vector terms))
          (map (lambda (column) (vector-ref positions column)) columns)))))))

;;; Plans retain ordered outputs, actions, slot count, purity and atom extent.
;;; Unsupported terms or clauses keep the complete rule on the general path.
;;; Slot assignment follows admitted body order. A fresh slot is always written
;;; before a bound read, so backtracking never needs to copy or clear the frame.
;; gerbil-ascent-compile-positive-plan
;;   : (-> Heads Body (Maybe PositivePlan))
;;   | doc m%
;;       Lower admitted atoms, expressions, guards and bindings into ordered
;;       slot actions. Other clause kinds retain the general interpreter.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-compile-positive-plan heads body)
;;       ;; => a slot plan for simple positive atoms
;;       ```
;;     %
(def (gerbil-ascent-compile-positive-plan heads body)
  (let/cc unsupported
    (let ((slots (make-hash-table-eq)) (scope #f) (count 0) (pure? #t))
      (def (ensure-scope!)
        ;; Materialize at the first consumer, once per plan. Pure rules keep
        ;; only their slot map; callbacks share subsequent immutable tails.
        (or scope (begin (set! scope (hash->list slots)) scope)))
      (def (read-slot name)
        (or (hash-get slots name) (unsupported #f)))
      (def (fresh-slot! name)
        (let (slot count)
          (set! count (+ count 1))
          (hash-put! slots name slot)
          ;; Private immutable tails preserve the scope at each call point.
          ;; Shadowing prepends a new identity; prior callbacks retain theirs.
          (when scope (set! scope (cons (cons name slot) scope)))
          slot))
      (def (lower-call names procedure diagnostic (payload #f) (visible (ensure-scope!)))
        (unless (and (list? names) (procedure? procedure)) (unsupported #f))
        (set! pure? #f)
        (let ((fast (gerbil-ascent-compile-frame-call procedure (map read-slot names)))
              (stable-inputs? (gerbil-ascent-compile-input-guard names)))
          (def (fallback current-procedure current-names frame)
            (gerbil-ascent-call-with-bindings current-procedure current-names
              (map (lambda (entry)
                     (cons (car entry) (vector-ref frame (cdr entry)))) visible)
              diagnostic))
          (if payload
            (lambda (frame)
              ;; The old expression protocol reads procedure before input names.
              (let* ((current-procedure (vector-ref payload 1))
                     (current-names (vector-ref payload 0)))
                (if (and (eq? current-procedure procedure)
                         (stable-inputs? current-names))
                  (fast frame)
                  (fallback current-procedure current-names frame))))
            (lambda (frame)
              (if (stable-inputs? names) (fast frame)
                  (fallback procedure names frame))))))
      (def (lower term head?)
        (case (car term)
          ((literal wildcard) term)
          ((expression)
           (let (payload (cdr term))
             (unless (and (vector? payload) (= (vector-length payload) 2))
               (unsupported #f))
             (cons 'expression (lower-call (vector-ref payload 0)
                                          (vector-ref payload 1) "unbound ASCENT expression variable" payload))))
          ((variable)
           (let (slot (hash-get slots (cdr term)))
             (cond
               (slot (cons 'bound slot))
               (head? (unsupported #f))
               (else (cons 'fresh (fresh-slot! (cdr term)))))))
          (else (unsupported #f))))
      (let* ((actions
               (map
                 (lambda (clause)
                   (case (vector-ref clause 0)
                     ((atom)
                      (let* ((atom (vector-ref clause 1))
                             (original (vector-ref atom 1))
                             (columns (vector-ref atom 2))
                             (prior-count count)
                             (_checked-columns
                              (unless (and (list? columns)
                                           (andmap (lambda (column)
                                                     (and (exact-integer? column)
                                                          (<= 0 column)
                                                          (< column (length original)))) columns))
                                (unsupported #f)))
                             (prior-scope
                               (and (ormap (lambda (term) (eq? (car term) 'expression)) original)
                                    (ensure-scope!)))
                             (terms (map (lambda (term) (lower term #f)) original))
                             (keys (map
                                     (lambda (source action)
                                       ;; Index access precedes this atom's row
                                       ;; matching. Only the prior bound prefix
                                       ;; may supply a key, even for a repeated
                                       ;; variable already tagged bound locally.
                                       (unless (or (eq? (car action) 'literal)
                                                   (and (eq? (car action) 'bound)
                                                        (< (cdr action) prior-count))
                                                   (and (eq? (car source) 'expression)
                                                        (andmap (lambda (name)
                                                                  (let (slot (hash-get slots name))
                                                                    (and slot (< slot prior-count))))
                                                                (vector-ref (cdr source) 0))))
                                         (unsupported #f))
                                       (if (eq? (car source) 'expression)
                                         (let (payload (cdr source))
                                           (cons 'expression
                                             (lower-call (vector-ref payload 0)
                                               (vector-ref payload 1)
                                               "unbound ASCENT expression variable"
                                               payload prior-scope)))
                                         action))
                                     (project-slot-terms original columns)
                                     (project-slot-terms terms columns))))
                        ;; Key evaluation precedes row matching. Changed inputs
                        ;; must not read row-local slots left by prior candidates.
                        (vector atom terms keys (compile-parts-matcher terms)
                                (compile-selected-parts-matcher terms columns keys))))
                     ((guard)
                      (vector 'guard (lower-call (vector-ref clause 1)
                                                (vector-ref clause 2) "unbound ASCENT clause variable")))
                     ((binding)
                      ;; Resolve inputs before shadowing the output name. A
                      ;; separate slot preserves enclosing backtracking values.
                      (let* ((call (lower-call (vector-ref clause 2)
                                               (vector-ref clause 3) "unbound ASCENT clause variable"))
                             (slot (fresh-slot! (vector-ref clause 1))))
                        (vector 'binding slot call)))
                     (else (unsupported #f)))) body))
             (outputs
               (map (lambda (head)
                      (let (terms (map (lambda (term) (lower term #t)) (vector-ref head 1)))
                        (vector head terms (compile-parts-output terms)))) heads)))
        (vector outputs (compile-action-segments actions) count pure?
                (length (filter (lambda (action) (vector? (vector-ref action 0))) actions)))))))

;;; Return the ordered callback prefix and its atom suffix as separate values.
;;; Structural recursion constructs only the detached prefix, without mutation.
;; : (-> OrderedActions (Values OrderedActions OrderedActions))
(def (callback-prefix actions)
  (match actions
    ([] (values [] []))
    ([action . remaining]
     (if (vector? (vector-ref action 0))
       (values [] actions)
       (let-values (((prefix suffix) (callback-prefix remaining)))
         (values (cons action prefix) suffix))))))

;;; Atom boundaries retain relation lookup and delta depth. Contiguous guards
;;; and bindings share one prepared continuation, preserving their exact order.
;; : (-> OrderedActions OrderedActions)
(def (compile-action-segments actions)
  (if (null? actions)
    []
    (if (vector? (vector-ref (car actions) 0))
      (cons (car actions) (compile-action-segments (cdr actions)))
      (let-values (((segment remaining)
                    (callback-prefix actions)))
        (cons (vector 'callbacks (gerbil-ascent-compile-frame-sequence segment))
              (compile-action-segments remaining))))))

;;; Project only head emissions; preserve every compiled body invariant.
;;; Both SCC ownership and source-update selection share this representation owner.
;; : (-> PositivePlan OrderedOutputs PositivePlan)
(def (gerbil-ascent-positive-plan-with-outputs plan outputs)
  (vector outputs (vector-ref plan 1) (vector-ref plan 2)
          (vector-ref plan 3) (vector-ref plan 4)))

;;; Execution representation and permission to reorder are separate facts.
;;; Callback plans execute serially even when their slot reads are compiled.
;; : (-> (Maybe PositivePlan) Boolean)
(def (gerbil-ascent-pure-positive-plan? plan)
  (and plan (vector-ref plan 3)))

;; : (-> Terms Row Frame Boolean)
(def (match-row! terms row frame)
  (if (null? terms)
    #t
    (let* ((term (car terms)) (value (car row)))
      (and (case (car term)
             ((fresh) (vector-set! frame (cdr term) value) #t)
             ((bound) (equal? (vector-ref frame (cdr term)) value))
             ((literal) (equal? (cdr term) value))
             ((expression) (equal? ((cdr term) frame) value))
             ((wildcard) #t))
           (match-row! (cdr terms) (cdr row) frame)))))

;; Bind each argument once; parts traversal uses this case directly rather
;; than making three additional matcher calls for every regenerated tuple.
(defrule (match-value! term value frame)
  (let ((selected term) (stored value) (bindings frame))
    (case (car selected)
      ((fresh) (vector-set! bindings (cdr selected) stored) #t)
      ((bound) (equal? (vector-ref bindings (cdr selected)) stored))
      ((literal) (equal? (cdr selected) stored))
      ((expression) (equal? ((cdr selected) bindings) stored))
      ((wildcard) #t))))
;; : (-> Terms Prefix Value Value Frame Boolean)
(def (match-parts! terms prefix left right frame)
  (if (pair? prefix)
    (and (match-value! (car terms) (car prefix) frame)
         (match-parts! (cdr terms) (cdr prefix) left right frame))
    (and (match-value! (car terms) left frame)
         (match-value! (cadr terms) right frame))))

;; Compile the frequent pure coordinate layouts once. Fall back for other
;; actions and shapes, retaining left-to-right failures and host callbacks.
(def (compile-parts-matcher terms)
  (let (tags (map car terms))
    (cond
      ((equal? tags '(fresh fresh))
       (let ((a (cdar terms)) (b (cdadr terms)))
         (lambda (prefix left right frame)
           (if (null? prefix)
             (begin (vector-set! frame a left) (vector-set! frame b right) #t)
             (match-parts! terms prefix left right frame)))))
      ((equal? tags '(fresh fresh fresh))
       (let ((a (cdar terms)) (b (cdadr terms)) (c (cdaddr terms)))
         (lambda (prefix left right frame)
           (if (and (pair? prefix) (null? (cdr prefix)))
             (begin (vector-set! frame a (car prefix)) (vector-set! frame b left)
                    (vector-set! frame c right) #t)
             (match-parts! terms prefix left right frame)))))
      ((equal? tags '(bound bound fresh))
       (let ((a (cdar terms)) (b (cdadr terms)) (c (cdaddr terms)))
         (lambda (prefix left right frame)
           (if (and (pair? prefix) (null? (cdr prefix)))
             (and (equal? (vector-ref frame a) (car prefix))
                  (equal? (vector-ref frame b) left)
                  (begin (vector-set! frame c right) #t))
             (match-parts! terms prefix left right frame)))))
      (else (lambda (prefix left right frame) (match-parts! terms prefix left right frame))))))

;; The synchronous index owner guarantees exact canonical key selection.
;; Only prior-bound actions present in the key can omit their second equality
;; test. Generic/overselecting row access continues to use the full matcher.
(def (compile-selected-parts-matcher terms columns keys)
  (and (equal? (map car terms) '(bound bound fresh))
       (member 0 columns) (member 1 columns)
       (andmap (lambda (column key) (equal? key (list-ref terms column))) columns keys)
       (let (slot (cdaddr terms))
         (lambda (prefix left right frame)
           (if (and (pair? prefix) (null? (cdr prefix)))
             (begin (vector-set! frame slot right) #t)
             (match-parts! terms prefix left right frame))))))

;; : (-> SlotTerm Frame Value)
(def (term-value term frame)
  (case (car term)
    ((literal) (cdr term))
    ((expression) ((cdr term) frame))
    (else (vector-ref frame (cdr term)))))

;; Terminal parts already own a proved frame. Compile common output slot
;; reads once; row consumers retain their original map path. The getter is
;; stored with its output, so projected/multiple heads preserve order/identity.
(def (compile-parts-output terms)
  (if (and (memq (length terms) '(1 2 3)) (andmap (lambda (term) (eq? (car term) 'bound)) terms))
    (let (slots (map cdr terms))
      (case (length slots)
        ((1) (let (a (car slots)) (lambda (frame) (list (vector-ref frame a)))))
        ((2) (let ((a (car slots)) (b (cadr slots)))
               (lambda (frame) (list (vector-ref frame a) (vector-ref frame b)))))
        (else (let ((a (car slots)) (b (cadr slots)) (c (caddr slots)))
                (lambda (frame) (list (vector-ref frame a) (vector-ref frame b) (vector-ref frame c)))))))
    (lambda (frame) (map (lambda (term) (term-value term frame)) terms))))
(def (emit-parts-heads! heads frame emit-row!)
  (unless (null? heads)
    (let (head (car heads))
      (emit-row! (vector-ref head 0)
        (if (> (vector-length head) 2) ((vector-ref head 2) frame)
            (map (lambda (term) (term-value term frame)) (vector-ref head 1)))))
    (emit-parts-heads! (cdr heads) frame emit-row!)))

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
(def (gerbil-ascent-run-positive-plan! plan frame delta-at rows-access emit-row! (checkpoint! #f) (parts-access #f))
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
  (visit-positive-atoms! (vector-ref plan 1) (vector-ref plan 0)
                        frame
                        delta-at 0 rows-access emit-row! checkpoint! parts-access))

;;; PartsAccess is private exact canonical selection, synchronous and complete.
;;; A false return must invoke no consumer; custom/overselecting providers use RowsAccess.
;;; Explicit rows keep the direct list loop; frozen views invoke a local visitor.
;; : (-> Atoms Heads Frame Integer Nat RowsAccess EmitRow Void)
(def (visit-positive-atoms! atoms heads frame delta-at depth rows-access emit-row! checkpoint! parts-access)
  (if (null? atoms)
    (let outputs ((remaining heads))
      (unless (null? remaining)
        (let (output (car remaining))
          (emit-row! (vector-ref output 0)
                     (map (lambda (term) (term-value term frame))
                          (vector-ref output 1))))
        (outputs (cdr remaining))))
    (let (action (car atoms))
      (case (vector-ref action 0)
        ((callbacks)
         (when ((vector-ref action 1) frame)
           (visit-positive-atoms! (cdr atoms) heads frame delta-at depth
                                  rows-access emit-row! checkpoint! parts-access)))
        (else
         (unless (and parts-access
                   (parts-access (vector-ref action 0) frame (= depth delta-at) (vector-ref action 2)
                     (lambda (prefix left right)
                       (when checkpoint! (checkpoint!))
                       (when ((or (vector-ref action 4) (vector-ref action 3)) prefix left right frame)
                         (if (null? (cdr atoms)) (emit-parts-heads! heads frame emit-row!)
                           (visit-positive-atoms! (cdr atoms) heads frame delta-at (+ depth 1)
                             rows-access emit-row! checkpoint! parts-access))))))
         (let (rows (rows-access (vector-ref action 0) frame
                                 (= depth delta-at) (vector-ref action 2)))
           (if (or (pair? rows) (null? rows))
             (let candidates ((remaining rows))
               (unless (null? remaining)
                 (when checkpoint! (checkpoint!))
                 (when (match-row! (vector-ref action 1) (car remaining) frame)
                   (visit-positive-atoms! (cdr atoms) heads frame delta-at (+ depth 1)
                                          rows-access emit-row! checkpoint! parts-access))
                 (candidates (cdr remaining))))
             (if (gerbil-ascent-row-parts? rows)
               (gerbil-ascent-for-each-row-parts
                (lambda (prefix left right)
                  (when checkpoint! (checkpoint!))
                  (when ((vector-ref action 3) prefix left right frame)
                    (visit-positive-atoms! (cdr atoms) heads frame delta-at (+ depth 1)
                                           rows-access emit-row! checkpoint! parts-access))) rows)
               (gerbil-ascent-for-each-row
                (lambda (row)
                  (when checkpoint! (checkpoint!))
                  (when (match-row! (vector-ref action 1) row frame)
                    (visit-positive-atoms! (cdr atoms) heads frame delta-at (+ depth 1)
                                           rows-access emit-row! checkpoint! parts-access))) rows))))))))))

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
