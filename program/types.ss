;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Rule declarations are Core POO contracts. Relation rows
;;; remain ordinary Scheme values; constructors check their declared arity.
(import (only-in :std/list/list delete-duplicates/hash)
        (only-in :clan/poo/object .o .cc .ref .ref/cached object-revision)
        (only-in :clan/poo/mop define-type element? validate Type. Any)
        (only-in :clan/poo/object-contract ObjectContract.)
        (only-in :yuanxu/types
                 YuanxuObjectContract.
                 yuanxu-predicate-contract)
        (only-in :gerbil-ascent/table/provider
                 GerbilAscentIndexProviderContract gerbil-ascent-canonical-hash-index-provider?)
        (only-in :gerbil-ascent/table/storage
                 GerbilAscentStorageProviderContract gerbil-ascent-canonical-set-storage-provider?))

(export canonical-value-check-current?
        gerbil-ascent-fact-limit?
        gerbil-ascent-make-term-value gerbil-ascent-make-atom-value
        gerbil-ascent-check-owned-term-value gerbil-ascent-check-owned-atom-value
        gerbil-ascent-make-rule-value gerbil-ascent-check-owned-rule-value
        gerbil-ascent-make-relation-value gerbil-ascent-check-owned-relation-value
        gerbil-ascent-relation-with-rows
        gerbil-ascent-make-session-value
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
  (yuanxu-predicate-contract identity predicate))

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
(define-type (GerbilAscentRelationContract @ YuanxuObjectContract.)
  identity: 'ascent/relation
  proto: (.o)
  responsibilities: (.o name: +symbol+ arity: +arity+ rows: +rows+
                      field-predicates: +field-predicates+
                      storage-kind: (clause-kind-contract 'relation)
                      index-provider: +provider+
                      storage-provider: +storage-provider+))

;;; A lattice owns a join operation; key refinement semantics are distinct
;;; from ordinary set insertion even when source rows have the same shape.
(define-type (GerbilAscentLatticeContract @ YuanxuObjectContract.)
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
(define-type (GerbilAscentTermContract @ YuanxuObjectContract.)
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
;; BEGIN GENERATED PREPARATION METADATA-GUARD
(def (canonical-metadata-current? contract slots)
  (let* ((fields (.ref contract 'responsibilities))
         (descriptors (cons contract (map (cut .ref fields <>) slots)))
         (sources (cons fields descriptors))
         (revisions (map object-revision sources))
         (classifiers (map (cut .ref <> '.classify) descriptors)))
    (lambda ()
      (and (andmap (lambda (source revision) (= (object-revision source) revision)) sources revisions)
           (eq? fields (.ref/cached contract 'responsibilities))
           (andmap (lambda (slot descriptor) (eq? (.ref/cached fields slot) descriptor)) slots (cdr descriptors))
           (andmap (lambda (descriptor classifier) (eq? (.ref/cached descriptor '.classify) classifier))
                   descriptors classifiers)))))
(def (canonical-value-member contract view slots)
  (let (current? (canonical-value-check-current? contract slots))
    (lambda (value)
      (if (current?) (element? view value) (element? contract value)))))
(def (canonical-validation-current? contract slots)
  (let* ((fields (.ref contract 'responsibilities))
         (descriptors (delete-duplicates/hash (map (cut .ref fields <>) slots) table: (make-hash-table-eq)))
         (missing (gensym 'missing-validation-protocol))
         (entries
          (apply append
            (map (lambda (entry)
                   (map (lambda (slot) (vector (car entry) slot (.ref (car entry) slot))) (cdr entry)))
                 (cons (cons contract '(.element? .validate .admit .obligations value-contract))
                       (map (lambda (field) (cons field '(.element? .admit .obligations value-contract))) descriptors))))))
    (lambda ()
      (andmap (lambda (entry)
                (eq? (vector-ref entry 2)
                     (.ref/cached (vector-ref entry 0) (vector-ref entry 1) (lambda () missing)))) entries))))
;;; Capture metadata/method identities for a callback-free compatible value view.
;;; The caller proves view compatibility; this predicate never admits a value.
;; : (-> Contract [Symbol] (-> Boolean))
(def (canonical-value-check-current? contract slots)
  (let ((metadata? (canonical-metadata-current? contract slots))
        (protocol? (canonical-validation-current? contract slots)))
    (lambda () (and (metadata?) (protocol?)))))
;; END GENERATED PREPARATION METADATA-GUARD

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

;; BEGIN GENERATED OWNED RELATION VALUE
(def (gerbil-ascent-make-relation-value prototype relation-name column-count source-rows
                                        predicates-value domain-value index-value storage-value)
  (remember-value-shape! 'relation
    (.o (:: @ prototype) name: relation-name arity: column-count rows: source-rows
        field-predicates: predicates-value checked-domain: domain-value storage-kind: 'relation
        index-provider: index-value storage-provider: storage-value)))

(def +relation-value+
  (.cc ObjectContract. identity: 'ascent/relation-value
       required-prototype: (.ref GerbilAscentRelationContract 'proto)
       extra-fields: 'delegate constraints: (list Any)
       responsibilities:
       (.o name: (.cc Type. .element?: symbol?)
           arity: (.cc Type. .element?: (lambda (value) (and (exact-integer? value) (<= 0 value))))
           rows: (.cc Type. .element?: list?)
           field-predicates: (.cc Type. .element?: (lambda (value) (and (list? value) (andmap procedure? value))))
           storage-kind: (.cc Type. .element?: (cut clause-kind? 'relation <>))
           index-provider: (.cc Type. .element?: gerbil-ascent-canonical-hash-index-provider?)
           storage-provider: (.cc Type. .element?: gerbil-ascent-canonical-set-storage-provider?))))
(def +relation-slots+ '(name arity rows field-predicates storage-kind index-provider storage-provider))
(def relation-metadata-current? (canonical-metadata-current? GerbilAscentRelationContract +relation-slots+))
(def relation-protocol-current? (canonical-validation-current? GerbilAscentRelationContract +relation-slots+))
;; These providers have no caller getter/callback on the selected path. Arbitrary
;; providers must enter complete admission once, preserving all callback order.
(def (owned-canonical-relation? value)
  (and (declared-value-shape? 'relation value)
       (gerbil-ascent-canonical-hash-index-provider? (.ref value 'index-provider))
       (gerbil-ascent-canonical-set-storage-provider? (.ref value 'storage-provider))
       (relation-metadata-current?)))
(def (relation-value? value)
  (if (and (owned-canonical-relation? value) (relation-protocol-current?))
      (element? +relation-value+ value) (element? GerbilAscentRelationContract value)))
(def (gerbil-ascent-check-owned-relation-value value)
  (if (and (owned-canonical-relation? value) (relation-protocol-current?)
           (element? +relation-value+ value)) value
      (validate GerbilAscentRelationContract value)))

;; END GENERATED OWNED RELATION VALUE

;;; Row-only private views retain the producer's field-specification ownership.
;;; This is not a validation receipt: every root still checks the current rows.
;;; POO's existing prototype dependency invalidation revokes the child's revision
;;; on any supported ancestor edit. Unknown or changed producers remain ordinary
;;; objects, preserving their getter and classifier protocols.
;; BEGIN GENERATED OWNED ROW VIEW
(def (gerbil-ascent-relation-with-rows relation replacement)
  (let (value (.o (:: @ relation) rows: replacement))
    (if (declared-value-shape? 'relation relation)
      (remember-value-shape! 'relation value)
      value)))
;; END GENERATED OWNED ROW VIEW

;; BEGIN GENERATED OWNED DECLARATION VALUES
(def term-value-current? (canonical-value-check-current? GerbilAscentTermContract '(kind value)))
(def (canonical-term-value? value)
  (if (term-value-current?) (element? +term-value+ value)
      (element? GerbilAscentTermContract value)))
;;; Check fresh factory values without retaining any successful admission.
;; : (-> Term Term)
(def (gerbil-ascent-check-owned-term-value value)
  (if (and (declared-value-shape? 'term value) (term-value-current?)
           (element? +term-value+ value)) value
      (validate GerbilAscentTermContract value)))
(def (term-value? value)
  (if (declared-value-shape? 'term value)
    (canonical-term-value? value)
    (element? GerbilAscentTermContract value)))
(def (terms-value? value)
  (and (list? value) (andmap term-value? value)))
(def +terms+ (slot-contract 'ascent/terms terms-value?))

;;; Atom plans bind one relation name to ordered terms and one open planning
;;; slot; the evaluator consumes the lowered plan without row-loop dispatch.
(define-type (GerbilAscentAtomContract @ YuanxuObjectContract.)
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

(def atom-value-check-current?
  (canonical-value-check-current? GerbilAscentAtomContract
                                  '(ascent-clause-kind relation terms .plan)))
(def (owned-atom-fields? value)
  (and (declared-value-shape? 'atom value) (term-value-current?)
       (let (terms (.ref value 'terms))
         (and (list? terms) (andmap (cut declared-value-shape? 'term <>) terms)))))
(def (atom-value? value)
  (if (owned-atom-fields? value) (canonical-atom-value? value)
      (element? GerbilAscentAtomContract value)))
;;; Unknown children or changed protocol dispatch use complete public admission.
;; : (-> Atom Atom)
(def (gerbil-ascent-check-owned-atom-value value)
  (if (and (owned-atom-fields? value) (atom-value-check-current?)
           (element? +atom-value+ value)) value
      (validate GerbilAscentAtomContract value)))


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
(define-type (GerbilAscentGuardContract @ YuanxuObjectContract.)
  identity: 'ascent/guard
  proto: (.o)
  responsibilities: (.o ascent-clause-kind: (clause-kind-contract 'guard)
                      variables: +variables+ predicate: +procedure+
                      checked-operator: +checked-operator+
                      .plan: +plan+))

;;; Generators may publish one variable or a tuple; the output descriptor
;;; rejects duplicate names before rows enter the evaluator.
(define-type (GerbilAscentGeneratorContract @ YuanxuObjectContract.)
  identity: 'ascent/generator
  proto: (.o)
  responsibilities: (.o ascent-clause-kind:
                      (clause-kind-contract 'generator)
                      variable: +generator-output+ variables: +variables+
                      generate: +procedure+ .plan: +plan+))

;;; Bindings compute one value from established inputs and introduce exactly
;;; one new variable to subsequent clauses.
(define-type (GerbilAscentBindingContract @ YuanxuObjectContract.)
  identity: 'ascent/binding
  proto: (.o)
  responsibilities: (.o ascent-clause-kind:
                      (clause-kind-contract 'binding)
                      variable: +symbol+ variables: +variables+
                      checked-operator: +checked-operator+
                      compute: +procedure+ .plan: +plan+))

;;; Negation is a read of a relation with no new binding; stratification
;;; ensures the referenced rows are stable before the check executes.
(define-type (GerbilAscentNegationContract @ YuanxuObjectContract.)
  identity: 'ascent/negation
  proto: (.o)
  responsibilities: (.o ascent-clause-kind:
                      (clause-kind-contract 'negation)
                      relation: +symbol+ terms: +terms+ .plan: +plan+))

;;; Aggregates consume a relation group and publish one result or a pattern
;;; tuple after the stratum's contributing rows have stabilized.
(define-type (GerbilAscentAggregateContract @ YuanxuObjectContract.)
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
(define-type (GerbilAscentRuleContract @ YuanxuObjectContract.)
  identity: 'ascent/rule
  proto: (.o)
  responsibilities: (.o heads: +heads+ body: +clauses+))

;;; Positive factory-owned Atom trees select a callback-free compatible view.
;;; Opaque clauses and changed admission protocols always keep public dispatch.
(def +rule-value+
  (.cc ObjectContract. identity: 'ascent/rule-value
       required-prototype: (.ref GerbilAscentRuleContract 'proto)
       extra-fields: 'delegate constraints: (list Any)
       responsibilities:
       (.o heads: (.cc Type. .element?: (lambda (heads)
             (and (pair? heads) (list? heads) (andmap atom-value? heads))))
           body: (.cc Type. .element?: (lambda (body)
             (and (list? body) (andmap atom-value? body)))))))
(def rule-value-current?
  (canonical-value-check-current? GerbilAscentRuleContract '(heads body)))
(def (owned-rule-fields? value)
  (and (declared-value-shape? 'rule value) (atom-value-check-current?)
       (term-value-current?)
       (let ((heads (.ref value 'heads)) (body (.ref value 'body)))
         (and (list? heads) (list? body)
              (andmap owned-atom-fields? heads) (andmap owned-atom-fields? body)))))
;; : (-> Prototype [Atom] [Clause] Rule)
(def (gerbil-ascent-make-rule-value prototype head-values body-values)
  (remember-value-shape! 'rule
    (.o (:: @ prototype) heads: head-values body: body-values)))
(def (rule-value? value)
  ;; A failed Atom may still enter another public clause descriptor. Preserve
  ;; those classifier/admission callbacks rather than treating view failure as rejection.
  (if (and (rule-value-current?) (owned-rule-fields? value)
           (element? +rule-value+ value)) #t
      (element? GerbilAscentRuleContract value)))
;; : (-> Rule Rule)
(def (gerbil-ascent-check-owned-rule-value value)
  (if (and (rule-value-current?) (owned-rule-fields? value)
           (element? +rule-value+ value)) value
      (validate GerbilAscentRuleContract value)))


(def +relations+
  (slot-contract 'ascent/relations
                 (lambda (value)
                   (and (list? value)
                        (andmap (lambda (relation)
                                  (or (relation-value? relation)
                                      (element? GerbilAscentLatticeContract relation)))
                                value)))))
(def +rules+
  (slot-contract 'ascent/rules
                 (lambda (value)
                   (and (list? value)
                        (andmap rule-value? value)))))

;; END GENERATED OWNED DECLARATION VALUES

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
(define-type (GerbilAscentFragmentContract @ YuanxuObjectContract.)
  identity: 'ascent/fragment
  proto: (.o)
  responsibilities:
  (.o relations: +relations+ rules: +rules+ exports: +fragment-exports+
      source-handles: +source-handles+))

;;; Program budgets bound accepted input, derived facts, and public output
;;; separately; source admission checks them before mutating a session.
(define-type (GerbilAscentProgramContract @ YuanxuObjectContract.)
  identity: 'ascent/program
  proto: (.o)
  responsibilities:
  (.o relations: +relations+
      rules: +rules+
      source-handles: +source-handles+
      max-input-facts: +fact-budget+
      max-derived-facts: +fact-budget+
      max-output-facts: +fact-budget+))

;;; Session operations are the only mutable public boundary. A run returns an
;;; immutable result snapshot even when later appends extend the session.
;; Prototype identity outlives the descriptor's lazily materialized slot cache.
;; Rematerialization must not invalidate already published native Sessions.
(def +session-prototype+ (.o))
(define-type (GerbilAscentSessionContract @ YuanxuObjectContract.)
  identity: 'ascent/session
  proto: +session-prototype+
  responsibilities:
  (.o .append-source!: +procedure+
      .replace-source!: +procedure+
      .run: +procedure+))

;; This factory owns all field getters. It checks every mandatory procedure on
;; each call, while explicit public/contextual admission keeps its full receipts.
(def +session-value+
  (.cc ObjectContract. identity: 'ascent/session-value
       required-prototype: +session-prototype+
       extra-fields: 'delegate constraints: (list Any)
       responsibilities:
       (.o .append-source!: (.cc Type. .element?: procedure?)
           .replace-source!: (.cc Type. .element?: procedure?)
           .run: (.cc Type. .element?: procedure?))))
(def session-metadata-current?
  (canonical-metadata-current? GerbilAscentSessionContract '(.append-source! .replace-source! .run)))
(def session-protocol-current?
  (canonical-validation-current? GerbilAscentSessionContract '(.append-source! .replace-source! .run)))
(def (gerbil-ascent-make-session-value append! replace! replace-all! run! timeout!)
  (let (value (.o (:: @ (.ref GerbilAscentSessionContract 'proto))
                .append-source!: append! .replace-source!: replace!
                .replace-sources!: replace-all! .run: run! .run-timeout: timeout!))
    (if (and (session-metadata-current?) (session-protocol-current?)
             (element? +session-value+ value))
      value
      (validate GerbilAscentSessionContract value))))
