;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Rule declarations are Core POO contracts. Relation rows
;;; remain ordinary Scheme values; constructors check their declared arity.
(import (only-in :clan/poo/object .o .cc .ref object-revision)
        (only-in :clan/poo/mop define-type element? Type. Any)
        (only-in :clan/poo/object-contract ObjectContract.)
        (only-in :core/types
                 PooFlowNativeObjectContract.
                 poo-flow-predicate-contract)
        (only-in :gerbil-ascent/table/provider
                 GerbilAscentIndexProviderContract gerbil-ascent-canonical-hash-index-provider?)
        (only-in :gerbil-ascent/table/storage
                 GerbilAscentStorageProviderContract gerbil-ascent-canonical-set-storage-provider?))

(export gerbil-ascent-fact-limit?
        gerbil-ascent-owned-root-contract
        gerbil-ascent-make-term-value gerbil-ascent-make-atom-value
        GerbilAscentRelationContract
        GerbilAscentLatticeContract
        GerbilAscentTermContract
        GerbilAscentAtomContract
        GerbilAscentGuardContract
        GerbilAscentGeneratorContract
        GerbilAscentBindingContract
        GerbilAscentNegationContract
        GerbilAscentAggregateContract
        GerbilAscentRuleContract
        GerbilAscentFragmentContract
        GerbilAscentProgramContract
        GerbilAscentSessionContract)

;; : (-> Symbol Procedure PredicateContract)
(def (slot-contract identity predicate)
  (poo-flow-predicate-contract identity predicate
                               (lambda (_value _context) [])))

(def +symbol+ (slot-contract 'ascent/symbol symbol?))
(def +arity+ (slot-contract 'ascent/arity
                           (lambda (value)
                             (and (exact-integer? value) (<= 0 value)))))
(def (gerbil-ascent-fact-limit? value)
  (or (eqv? value +inf.0)
      (and (exact-integer? value) (> value 0))))
(def +fact-budget+
  (slot-contract 'ascent/fact-budget gerbil-ascent-fact-limit?))
(def +rows+ (slot-contract 'ascent/rows list?))
(def +field-predicates+
  (slot-contract 'ascent/field-predicates
                 (lambda (value)
                   (and (list? value) (andmap procedure? value)))))
(def +provider+
  (slot-contract 'ascent/index-provider
                 (lambda (value)
                   ;; This exact receiver was validated when its module loaded.
                   ;; Derived/custom objects have another identity and retain
                   ;; the complete receiver contract, including missing slots.
                   (or (gerbil-ascent-canonical-hash-index-provider? value)
                       (element? GerbilAscentIndexProviderContract value)))))
(def +storage-provider+
  (slot-contract 'ascent/storage-provider
                 (lambda (value)
                   (or (gerbil-ascent-canonical-set-storage-provider? value)
                       (element? GerbilAscentStorageProviderContract value)))))
(def (term-kind? value)
  (memq value '(variable wildcard literal expression pattern)))
(def +term-kind+ (slot-contract 'ascent/term-kind term-kind?))
(def +any+ (slot-contract 'ascent/value (lambda (_value) #t)))
(def +plan+ (slot-contract 'ascent/clause-plan procedure?))
;; : (-> Symbol PredicateContract)
(def (clause-kind? expected value) (eq? value expected))
(def (clause-kind-contract kind)
  (slot-contract 'ascent/clause-kind (cut clause-kind? kind <>)))

;;; Relation shape checks arity, source rows, and physical providers before
;;; the evaluator creates any mutable table state.
(define-type (GerbilAscentRelationContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/relation
  proto: (.o)
  responsibilities: (.o name: +symbol+ arity: +arity+ rows: +rows+
                      field-predicates: +field-predicates+
                      storage-kind: (clause-kind-contract 'relation)
                      index-provider: +provider+
                      storage-provider: +storage-provider+))

;;; A lattice owns a join operation; key refinement semantics are distinct
;;; from ordinary set insertion even when source rows have the same shape.
(define-type (GerbilAscentLatticeContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/lattice
  proto: (.o)
  responsibilities: (.o name: +symbol+ arity: +arity+ rows: +rows+
                      field-predicates: +field-predicates+
                      storage-kind: (clause-kind-contract 'lattice)
                      join: (slot-contract 'ascent/lattice-join procedure?)
                      checked-operator:
                      (slot-contract 'ascent/lattice-checked-operator
                                     (lambda (value)
                                       (or (not value) (vector? value))))
                      index-provider: +provider+))

;;; Terms retain tagged source intent until planning can resolve variables and
;;; construct executable expression and pattern operations.
(define-type (GerbilAscentTermContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/term
  proto: (.o)
  responsibilities: (.o kind: +term-kind+ value: +any+))

;; Nested membership consumes a Boolean, not a contextual receipt. Reuse
;; the upstream value Type with the same ancestry, fields and kind predicate;
;; explicit Term admission still uses the complete public Flow Contract above.
(def +term-value+
  (.cc ObjectContract. identity: 'ascent/term-value
       required-prototype: (.ref GerbilAscentTermContract 'proto)
       extra-fields: 'delegate constraints: (list Any)
       responsibilities: (.o kind: (.cc Type. .element?: term-kind?) value: Any)))


;; Retain public descriptor mutation and classifier instrumentation. POO revisions
;; invalidate ordinary metadata edits; classifier identity also detects the
;; existing direct instance instrumentation used by the semantic cost control.
;; This caches descriptor identity only, never the result for an input value.
(def (canonical-value-member contract view slots)
  (let* ((fields (.ref contract 'responsibilities))
         (descriptors (cons contract (map (cut .ref fields <>) slots)))
         (sources (cons fields descriptors))
         (revisions (map object-revision sources))
         (classifiers (map (cut .ref <> '.classify) descriptors)))
    (lambda (value)
      (if (and (andmap (lambda (source revision) (= (object-revision source) revision))
                       sources revisions)
               (eq? fields (.ref contract 'responsibilities))
               (andmap (lambda (slot descriptor) (eq? (.ref fields slot) descriptor))
                       slots (cdr descriptors))
               (andmap (lambda (descriptor classifier)
                         (eq? (.ref descriptor '.classify) classifier))
                       descriptors classifiers))
        (element? view value)
        (element? contract value)))))

(def declared-value-shapes (make-hash-table test: eq? weak-keys: #t))

;; Only the constructors below issue a shape entry. It contains no candidate
;; reference or validation result; weak keys do not retain declarations.
(def (remember-value-shape! kind value)
  (when (= (object-revision value) 0)
    (hash-put! declared-value-shapes value (cons kind 0)))
  value)
;; BEGIN GENERATED PREPARATION VALUE-SHAPE
(def (declared-value-shape? kind value)
  (let (entry (hash-get declared-value-shapes value))
    (and entry (eq? kind (car entry)) (= (object-revision value) (cdr entry)))))
;; END GENERATED PREPARATION VALUE-SHAPE

;; These factories own every field specification. Arbitrary caller objects
;; cannot acquire a shape entry, and later POO edits invalidate it.
(def (gerbil-ascent-make-term-value prototype tag payload)
  (remember-value-shape! 'term
    (.o (:: @ prototype) kind: tag value: payload)))
(def (gerbil-ascent-make-atom-value prototype relation-name atom-terms lower)
  (remember-value-shape! 'atom
    (.o (:: self prototype) ascent-clause-kind: 'atom
        relation: relation-name terms: atom-terms
        (.plan (lambda (atom-plan bound) (lower self atom-plan bound))))))

(def canonical-term-value?
  (canonical-value-member GerbilAscentTermContract +term-value+ '(kind value)))
(def (term-value? value)
  (if (declared-value-shape? 'term value)
    (canonical-term-value? value)
    (element? GerbilAscentTermContract value)))
(def (terms-value? value)
  (and (list? value) (andmap term-value? value)))
(def +terms+ (slot-contract 'ascent/terms terms-value?))

;;; Atom plans bind one relation name to ordered terms and one open planning
;;; slot; the evaluator consumes the lowered plan without row-loop dispatch.
(define-type (GerbilAscentAtomContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/atom
  proto: (.o)
  responsibilities: (.o ascent-clause-kind: (clause-kind-contract 'atom)
                      relation: +symbol+ terms: +terms+ .plan: +plan+))

;; Rule membership also consumes only the Atom's value classification.
;; The public Atom descriptor retains its original contextual responsibilities.
(def +atom-value+
  (.cc ObjectContract. identity: 'ascent/atom-value
       required-prototype: (.ref GerbilAscentAtomContract 'proto)
       extra-fields: 'delegate constraints: (list Any)
       responsibilities:
       (.o ascent-clause-kind: (.cc Type. .element?: (cut clause-kind? 'atom <>))
           relation: (.cc Type. .element?: symbol?)
           terms: (.cc Type. .element?: terms-value?)
           .plan: (.cc Type. .element?: procedure?))))

(def canonical-atom-value?
  (canonical-value-member GerbilAscentAtomContract +atom-value+
                          '(ascent-clause-kind relation terms .plan)))

(def (atom-value? value)
  (if (and (declared-value-shape? 'atom value)
           (let (terms (.ref value 'terms))
             (and (list? terms) (andmap (cut declared-value-shape? 'term <>) terms))))
    (canonical-atom-value? value)
    (element? GerbilAscentAtomContract value)))

(def +variables+
  (slot-contract 'ascent/variables
                 (lambda (value)
                   (and (list? value) (andmap symbol? value)))))
(def +generator-output+
  (slot-contract
   'ascent/generator-output
   (lambda (value)
     (or (symbol? value)
         (and (pair? value)
              (list? value)
              (let loop ((remaining value) (seen []))
                (or (null? remaining)
                    (and (symbol? (car remaining))
                         (not (memq (car remaining) seen))
                         (loop (cdr remaining)
                               (cons (car remaining) seen))))))))))
(def +procedure+ (slot-contract 'ascent/procedure procedure?))
(def +optional-procedure+
  (slot-contract 'ascent/optional-procedure
                 (lambda (value) (or (not value) (procedure? value)))))
(def +checked-operator+
  (slot-contract 'ascent/checked-operator
                 (lambda (value) (or (not value) (vector? value)))))

;;; Guards can inspect only previously bound variables, which the planner
;;; checks before the predicate reaches execution.
(define-type (GerbilAscentGuardContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/guard
  proto: (.o)
  responsibilities: (.o ascent-clause-kind: (clause-kind-contract 'guard)
                      variables: +variables+ predicate: +procedure+
                      checked-operator: +checked-operator+
                      .plan: +plan+))

;;; Generators may publish one variable or a tuple; the output descriptor
;;; rejects duplicate names before rows enter the evaluator.
(define-type (GerbilAscentGeneratorContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/generator
  proto: (.o)
  responsibilities: (.o ascent-clause-kind:
                      (clause-kind-contract 'generator)
                      variable: +generator-output+ variables: +variables+
                      generate: +procedure+ .plan: +plan+))

;;; Bindings compute one value from established inputs and introduce exactly
;;; one new variable to subsequent clauses.
(define-type (GerbilAscentBindingContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/binding
  proto: (.o)
  responsibilities: (.o ascent-clause-kind:
                      (clause-kind-contract 'binding)
                      variable: +symbol+ variables: +variables+
                      checked-operator: +checked-operator+
                      compute: +procedure+ .plan: +plan+))

;;; Negation is a read of a relation with no new binding; stratification
;;; ensures the referenced rows are stable before the check executes.
(define-type (GerbilAscentNegationContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/negation
  proto: (.o)
  responsibilities: (.o ascent-clause-kind:
                      (clause-kind-contract 'negation)
                      relation: +symbol+ terms: +terms+ .plan: +plan+))

;;; Aggregates consume a relation group and publish one result or a pattern
;;; tuple after the stratum's contributing rows have stabilized.
(define-type (GerbilAscentAggregateContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/aggregate
  proto: (.o)
  responsibilities: (.o ascent-clause-kind:
                      (clause-kind-contract 'aggregate)
                      variable: +generator-output+ relation: +symbol+
                      terms: +terms+ variables: +variables+
                      aggregate: +procedure+
                      checked-operator: +checked-operator+
                      output-pattern: +optional-procedure+
                      .plan: +plan+))

(def +clauses+
  (slot-contract 'ascent/clauses
                 (lambda (value)
                   (and (list? value)
                        (andmap (lambda (clause)
                                  (or (atom-value? clause)
                                      (element? GerbilAscentGuardContract clause)
                                      (element? GerbilAscentGeneratorContract clause)
                                      (element? GerbilAscentBindingContract clause)
                                      (element? GerbilAscentNegationContract clause)
                                      (element? GerbilAscentAggregateContract clause)))
                                value)))))
(def +heads+
  (slot-contract 'ascent/heads
                 (lambda (value)
                   (and (pair? value)
                        (list? value)
                        (andmap (lambda (head)
                                  (atom-value? head))
                                value)))))

;;; A rule has at least one head and an ordered body. Shared body bindings
;;; make a multi-head rule one logical derivation event.
(define-type (GerbilAscentRuleContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/rule
  proto: (.o)
  responsibilities: (.o heads: +heads+ body: +clauses+))

(def +relations+
  (slot-contract 'ascent/relations
                 (lambda (value)
                   (and (list? value)
                        (andmap (lambda (relation)
                                  (or (element? GerbilAscentRelationContract relation)
                                      (element? GerbilAscentLatticeContract relation)))
                                value)))))
(def +rules+
  (slot-contract 'ascent/rules
                 (lambda (value)
                   (and (list? value)
                        (andmap (lambda (rule)
                                  (element? GerbilAscentRuleContract rule))
                                value)))))

;;; A fragment publishes an export resolver rather than a mutable mapping.
;;; The constructor copies and checks labels before closing over them.
(def +fragment-exports+
  (slot-contract 'ascent/fragment-exports procedure?))
(def +source-handles+
  (slot-contract 'ascent/source-handles
                 (lambda (value)
                   (and (list? value) (andmap symbol? value)))))

;;; A fragment carries declarations, rules and instance-local public handles.
;;; It has no execution limits until composition into a bounded program.
(define-type (GerbilAscentFragmentContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/fragment
  proto: (.o)
  responsibilities:
  (.o relations: +relations+ rules: +rules+ exports: +fragment-exports+
      source-handles: +source-handles+))

;;; Program budgets bound accepted input, derived facts, and public output
;;; separately; source admission checks them before mutating a session.
(define-type (GerbilAscentProgramContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/program
  proto: (.o)
  responsibilities:
  (.o relations: +relations+
      rules: +rules+
      source-handles: +source-handles+
      max-input-facts: +fact-budget+
      max-derived-facts: +fact-budget+
      max-output-facts: +fact-budget+))

;;; Inert construction owns every generated Term until root publication.
;;; Refine only nested responsibilities: ordinary public contracts stay exact.
;;; A successful Term check may be reused by identity within this one root;
;;; list shape, atom/rule shape and every other responsibility are still checked.
;; gerbil-ascent-owned-root-contract
;; : (forall (c) (-> c c))
;; : (-> DeclarationRootContract OwnedDeclarationRootContract)
;; | doc m%
;;     Build an invocation-local POO responsibility refinement for a private
;;     canonical declaration graph. No supplied callback can observe or mutate
;;     its Terms before publication. Do not use for caller-owned declarations.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-owned-root-contract GerbilAscentProgramContract)
;;     ;; => a private root contract retaining all Program responsibilities
;;     ```
;;   %
(def (gerbil-ascent-owned-root-contract root)
  (let* ((accepted (make-hash-table-eq))
         (owned-terms
          (slot-contract 'ascent/terms
            (lambda (value)
              (and (list? value)
                   (andmap (lambda (term)
                             (or (hash-get accepted term)
                                 (and (element? GerbilAscentTermContract term)
                                      (begin (hash-put! accepted term #t) #t)))) value)))))
         (owned-atom
          (.o (:: @ GerbilAscentAtomContract)
              proto: (.ref GerbilAscentAtomContract 'proto)
              responsibilities:
              (.o (:: @ (.ref GerbilAscentAtomContract 'responsibilities)) terms: owned-terms)))
         (owned-heads
          (slot-contract 'ascent/heads
            (lambda (value)
              (and (pair? value) (list? value) (andmap (cut element? owned-atom <>) value)))))
         (owned-body
          (slot-contract 'ascent/clauses
            (lambda (value)
              (and (list? value)
                   (andmap (lambda (clause)
                             (or (element? owned-atom clause)
                                 (element? +clauses+ (list clause)))) value)))))
         (owned-rule
          (.o (:: @ GerbilAscentRuleContract)
              proto: (.ref GerbilAscentRuleContract 'proto)
              responsibilities:
              (.o (:: @ (.ref GerbilAscentRuleContract 'responsibilities))
                  heads: owned-heads body: owned-body)))
         (owned-rules
          (slot-contract 'ascent/rules
            (lambda (value) (and (list? value) (andmap (cut element? owned-rule <>) value))))))
    ;; The inherited proto slot is a constructor, not a shared constant.
    ;; Bind the admitted parent's prototype explicitly on every refinement.
    (.o (:: @ root) proto: (.ref root 'proto)
        responsibilities: (.o (:: @ (.ref root 'responsibilities)) rules: owned-rules))))

;;; Session operations are the only mutable public boundary. A run returns an
;;; immutable result snapshot even when later appends extend the session.
;; Prototype identity outlives the descriptor's lazily materialized slot cache.
;; Rematerialization must not invalidate already published native Sessions.
(def +session-prototype+ (.o))
(define-type (GerbilAscentSessionContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/session
  proto: +session-prototype+
  responsibilities:
  (.o .append-source!: +procedure+
      .replace-source!: +procedure+
      .run: +procedure+))
