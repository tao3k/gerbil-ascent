;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Private positive-rule execution plans. Plans are immutable and shared;
;;; each engine owns its variable frames, including nested/concurrent solves.
(import (only-in :gerbil-ascent/core/rule-bindings gerbil-ascent-expression-value gerbil-ascent-head-row))
(export gerbil-ascent-prepare-rule-activations gerbil-ascent-positive-plan gerbil-ascent-compile-positive-plan gerbil-ascent-run-positive-plan!
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

;;; Unsupported terms or clauses keep the complete rule on the general path.
;;; Slot assignment follows admitted body order. A fresh slot is always written
;;; before a bound read, so backtracking never needs to copy or clear the frame.
;; gerbil-ascent-compile-positive-plan
;;   : (-> Heads Body (Maybe PositivePlan))
;;   | doc m%
;;       Lower ordered variable, literal and wildcard atoms into numeric slot actions. Clauses with callbacks retain the general interpreter.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-compile-positive-plan heads body)
;;       ;; => a slot plan for simple positive atoms
;;       ```
;;     %
(def (gerbil-ascent-compile-positive-plan heads body)
  (def (simple? atom)
    (andmap (lambda (term) (memq (car term) '(variable literal wildcard)))
            (vector-ref atom 1)))
  (and (andmap simple? heads)
       (andmap (lambda (clause)
                 (and (eq? (vector-ref clause 0) 'atom)
                      (simple? (vector-ref clause 1)))) body)
       (let ((slots (make-hash-table-eq)) (count 0))
         (def (lower term)
           (case (car term)
             ((literal wildcard) term)
             (else
              (let (slot (hash-get slots (cdr term)))
                (if slot
                  (cons 'bound slot)
                  (let (fresh count)
                    (set! count (+ count 1))
                    (hash-put! slots (cdr term) fresh)
                    (cons 'fresh fresh)))))))
         (let* ((atoms
                 (map (lambda (clause)
                        (let* ((atom (vector-ref clause 1))
                               (terms (map lower (vector-ref atom 1)))
                               (columns (vector-ref atom 2)))
                          (vector atom terms
                                  ;; Full ordered wide keys need no positional
                                  ;; reads. Copy the spine, retaining action
                                  ;; identity without aliasing the term list.
                                  (match columns
                                    ([] [])
                                    ([column] (list (list-ref terms column)))
                                    (else
                                     (if (and (>= (length columns) 128)
                                              (let loop ((xs terms) (ks columns) (n 0))
                                                (if (null? xs)
                                                  (null? ks)
                                                  (and (pair? ks) (= (car ks) n)
                                                       (loop (cdr xs) (cdr ks) (+ n 1))))))
                                       (map (lambda (term) term) terms)
                                       (map (lambda (column) (list-ref terms column)) columns))))))) body))
                (outputs
                 (map (lambda (head)
                        (vector head
                                (map (lambda (term)
                                       (if (eq? (car term) 'literal)
                                         term
                                         (cons 'bound (hash-get slots (cdr term)))))
                                     (vector-ref head 1)))) heads)))
           (vector outputs atoms count)))))

;; : (-> Terms Row Frame Boolean)
(def (match-row! terms row frame)
  (if (null? terms)
    #t
    (let* ((term (car terms)) (value (car row)))
      (and (case (car term)
             ((fresh) (vector-set! frame (cdr term) value) #t)
             ((bound) (equal? (vector-ref frame (cdr term)) value))
             ((literal) (equal? (cdr term) value))
             ((wildcard) #t))
           (match-row! (cdr terms) (cdr row) frame)))))

;; : (-> SlotTerm Frame Value)
(def (term-value term frame)
  (if (eq? (car term) 'literal) (cdr term) (vector-ref frame (cdr term))))

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
    (let* ((atom (car atoms))
           (rows (rows-access (vector-ref atom 0) frame
                              (= depth delta-at) (vector-ref atom 2))))
      (let candidates ((remaining rows))
        (unless (null? remaining)
          (when checkpoint! (checkpoint!))
          (when (match-row! (vector-ref atom 1) (car remaining) frame)
            (visit-positive-atoms! (cdr atoms) heads frame delta-at (+ depth 1)
                                   rows-access emit-row! checkpoint!))
          (candidates (cdr remaining)))))))

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
