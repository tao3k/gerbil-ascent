;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Immutable positive-rule lowering and frame matcher construction.
;;; Engines own mutable frames; the compiler cache contains no evaluation state.
(import (only-in :clan/poo/support/base lambda-match)
        (only-in "ordered-call.ss" dispatch-ordered-call)
        (only-in "rule-bindings.ss" gerbil-ascent-call-with-bindings)
        (only-in "positive-certificate.ss" gerbil-ascent-positive-certificate?)
        (only-in "expression-plan.ss" gerbil-ascent-compile-checked-frame-call
                 gerbil-ascent-compile-frame-sequence))
(export gerbil-ascent-positive-plan gerbil-ascent-compile-positive-plan
        gerbil-ascent-positive-plan-with-outputs gerbil-ascent-pure-positive-plan?
        match-row! match-parts! term-value)

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

;;; Fuse admitted column selection with ordered key lowering. Source and slot
;;; views have the same width; no intermediate selected spines escape or form.
;;; Only the mapper may prepare a key action, in the original column order.
;; : (forall (a b c) (-> (-> a b c) [a] [b] [Integer] [c]))
;; : (-> KeyLowering SourceTerms SlotTerms Columns KeyActions)
(def (map-projected-terms lower original slots columns)
  ((lambda-match
    ([] [])
    ([column] (list (lower (list-ref original column) (list-ref slots column))))
    (else
     (def (increasing? remaining prior)
       (or (null? remaining)
           (and (> (car remaining) prior)
                (increasing? (cdr remaining) (car remaining)))))
     (if (increasing? columns -1)
       (let select ((sources original) (actions slots) (selected columns) (position 0))
         (if (null? selected) []
           (if (= position (car selected))
             (let (key (lower (car sources) (car actions)))
               (cons key (select (cdr sources) (cdr actions) (cdr selected) (+ position 1))))
             (select (cdr sources) (cdr actions) selected (+ position 1)))))
       (let ((sources (list->vector original)) (actions (list->vector slots)))
         (map (lambda (column)
                (lower (vector-ref sources column) (vector-ref actions column))) columns))))) columns))

;; : (-> Body Natural)
;; Reserve only for variable occurrences in the first source atom. Repeated
;; variables may overestimate demand, so keep this hint bounded.
(def (initial-slot-capacity body)
  (if (and (pair? body) (vector? (car body)) (>= (vector-length (car body)) 2)
           (eq? (vector-ref (car body) 0) 'atom))
    (let (atom (vector-ref (car body) 1))
      (if (and (vector? atom) (>= (vector-length atom) 2))
        (let (terms (vector-ref atom 1))
          (if (and (list? terms) (>= (length terms) 64))
            (let scan ((pending terms) (count 0))
              (if (or (null? pending) (= count 4096)) count
                (let (term (car pending))
                  (scan (cdr pending)
                    (if (and (pair? term) (eq? (car term) 'variable)) (+ count 1) count)))))
            0))
        0))
    0))

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
    (let* ((capacity (initial-slot-capacity body))
           (slots (if (>= capacity 64) (make-hash-table-eq size: capacity) (make-hash-table-eq)))
           (scope #f) (count 0) (pure? #t))
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
        (gerbil-ascent-compile-checked-frame-call procedure names (map read-slot names)
          (lambda (current-procedure current-names frame)
            (gerbil-ascent-call-with-bindings current-procedure current-names
              (map (lambda (entry)
                     (cons (car entry) (vector-ref frame (cdr entry)))) visible)
              diagnostic))
          payload))
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
                                           ;; Keep this shape fact local to admission, rather than
                                           ;; retaining it in the slot-lowering lexical scope.
                                           (let (width (length original))
                                             (andmap (lambda (column)
                                                       (and (exact-integer? column)
                                                            (<= 0 column) (< column width))) columns)))
                                (unsupported #f)))
                             (prior-scope
                               (and (ormap (lambda (term) (eq? (car term) 'expression)) original)
                                    (ensure-scope!)))
                             (terms (map (lambda (term) (lower term #f)) original))
                             (keys (map-projected-terms
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
                                     original terms columns)))
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
        (let (plan
              (if pure?
                ;; A pure body emitted only atom actions. Keep its private
                ;; spine and count it directly instead of copying it twice.
                (vector outputs actions count #t (length actions))
                (vector outputs (compile-action-segments actions) count #f
                  (length (filter (lambda (action) (vector? (vector-ref action 0))) actions)))))
          (when (and pure? (not (gerbil-ascent-positive-certificate? heads body plan)))
            (error "ASCENT positive compiler certificate rejected"))
          plan)))))

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

;;; A coordinate matcher owns one shape guard and its complete fallback. The
;;; caller supplies hygienic parameter names; no reader closure is added per row.
(defrule (parts-matcher terms (prefix left right frame) shape? body)
  (lambda (prefix left right frame)
    (if shape? body (match-parts! terms prefix left right frame))))

;; Compile frequent pure coordinate layouts by matching the complete terms.
;; No temporary tag spine is needed; source slot IDs are captured once.
(def (compile-parts-matcher terms)
  (match terms
    ([['fresh . a] ['fresh . b]]
     (parts-matcher terms (prefix left right frame) (null? prefix)
       (begin (vector-set! frame a left) (vector-set! frame b right) #t)))
    ([['fresh . a] ['fresh . b] ['fresh . c]]
     (parts-matcher terms (prefix left right frame)
       (and (pair? prefix) (null? (cdr prefix)))
       (begin (vector-set! frame a (car prefix)) (vector-set! frame b left)
              (vector-set! frame c right) #t)))
    ([['bound . a] ['bound . b] ['fresh . c]]
     (parts-matcher terms (prefix left right frame)
       (and (pair? prefix) (null? (cdr prefix)))
       (and (equal? (vector-ref frame a) (car prefix))
            (equal? (vector-ref frame b) left)
            (begin (vector-set! frame c right) #t))))
    (else #f)))

;; The synchronous index owner guarantees exact canonical key selection.
;; Only prior-bound actions present in the key can omit their second equality
;; test. Generic/overselecting row access continues to use the full matcher.
(def (compile-selected-parts-matcher terms columns keys)
  (match terms
    ([['bound . _] ['bound . _] ['fresh . slot]]
     (and (member 0 columns) (member 1 columns)
          (andmap (lambda (column key) (equal? key (list-ref terms column))) columns keys)
          (parts-matcher terms (prefix left right frame)
            (and (pair? prefix) (null? (cdr prefix)))
            (begin (vector-set! frame slot right) #t))))
    (else #f)))

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
  (if (and (<= (length terms) 4)
           (andmap (lambda (term) (eq? (car term) 'bound)) terms))
    (dispatch-ordered-call (lambda (frame)) list (map cdr terms)
      (slot (vector-ref frame slot)))
    (lambda (frame) (map (lambda (term) (term-value term frame)) terms))))
