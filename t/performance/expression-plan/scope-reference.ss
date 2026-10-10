;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Private positive-rule execution plans. Plans are immutable and shared;
;;; each engine owns its variable frames, including nested/concurrent solves.
(import (only-in :gerbil-ascent/core/expression-plan gerbil-ascent-compile-frame-call gerbil-ascent-compile-frame-sequence
                 gerbil-ascent-compile-input-guard)
        (only-in :gerbil-ascent/core/rule-bindings gerbil-ascent-expression-value gerbil-ascent-head-row gerbil-ascent-call-with-bindings))
(export gerbil-ascent-prepare-rule-activations gerbil-ascent-positive-plan gerbil-ascent-compile-positive-plan gerbil-ascent-run-positive-plan!
        gerbil-ascent-pure-positive-plan?
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

;;; Plans retain ordered outputs, actions, slot count and a separate purity flag.
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
    (let ((slots (make-hash-table-eq)) (count 0) (pure? #t))
      (def (read-slot name)
        (or (hash-get slots name) (unsupported #f)))
      (def (fresh-slot! name)
        (let (slot count)
          (set! count (+ count 1))
          (hash-put! slots name slot)
          slot))
      (def (lower-call names procedure diagnostic (payload #f) (scope (hash->list slots)))
        (unless (and (list? names) (procedure? procedure)) (unsupported #f))
        (set! pure? #f)
        (let ((fast (gerbil-ascent-compile-frame-call procedure (map read-slot names)))
              (stable-inputs? (gerbil-ascent-compile-input-guard names)))
          (def (fallback current-procedure current-names frame)
            (gerbil-ascent-call-with-bindings current-procedure current-names
              (map (lambda (entry)
                     (cons (car entry) (vector-ref frame (cdr entry)))) scope)
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
                             (prior-scope (hash->list slots))
                             (original (vector-ref atom 1))
                             (terms (map (lambda (term) (lower term #f)) original))
                             (columns (vector-ref atom 2))
                             (keys (map
                                     (lambda (source action)
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
                        (vector atom terms keys)))
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
                      (vector head (map (lambda (term) (lower term #t))
                                        (vector-ref head 1)))) heads)))
        (vector outputs (compile-action-segments actions) count pure?)))))

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

;; : (-> SlotTerm Frame Value)
(def (term-value term frame)
  (case (car term)
    ((literal) (cdr term))
    ((expression) ((cdr term) frame))
    (else (vector-ref frame (cdr term)))))

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
(def (gerbil-ascent-run-positive-plan! plan frame delta-at rows-access emit-row! (checkpoint! #f))
  (visit-positive-atoms! (vector-ref plan 1) (vector-ref plan 0)
                        frame
                        delta-at 0 rows-access emit-row! checkpoint!))

;;; Recursion passes the frame explicitly; no closure is allocated per pivot.
;; : (-> Atoms Heads Frame Integer Nat RowsAccess EmitRow Void)
(def (visit-positive-atoms! atoms heads frame delta-at depth rows-access emit-row! checkpoint!)
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
                                  rows-access emit-row! checkpoint!)))
        (else
         (let (rows (rows-access (vector-ref action 0) frame
                                 (= depth delta-at) (vector-ref action 2)))
           (let candidates ((remaining rows))
             (unless (null? remaining)
               (when checkpoint! (checkpoint!))
               (when (match-row! (vector-ref action 1) (car remaining) frame)
                 (visit-positive-atoms! (cdr atoms) heads frame delta-at (+ depth 1)
                                        rows-access emit-row! checkpoint!))
               (candidates (cdr remaining))))))))))

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
