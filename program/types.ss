;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Rule declarations are Core POO contracts. Relation rows
;;; remain ordinary Scheme values; constructors check their declared arity.

(import "declaration-contract.ss"
        (only-in :std/list/list delete-duplicates/hash)
        (only-in :clan/poo/object .o .cc .ref .ref/cached object-revision)
        (only-in :clan/poo/mop define-type element? validate Type. Any)
        (only-in :clan/poo/type Record)
        (only-in :clan/poo/object-contract ObjectContract.)
        (only-in :yuanxu/object-types/contracts
                 YuanxuObjectContract. YuanxuContract.
                 yuanxu-predicate-contract)
        (only-in :gerbil-ascent/table/provider
                 GerbilAscentIndexProviderContract gerbil-ascent-canonical-hash-index-provider?)
        (only-in :gerbil-ascent/table/storage
                 GerbilAscentStorageProviderContract gerbil-ascent-canonical-set-storage-provider?))

(export
  ProgramScopeContract
  canonical-value-check-current?
  gerbil-ascent-fact-limit?
  gerbil-ascent-make-term-value
  gerbil-ascent-make-atom-value
  gerbil-ascent-check-owned-term-value
  gerbil-ascent-check-owned-atom-value
  gerbil-ascent-make-rule-value
  gerbil-ascent-check-owned-rule-value
  gerbil-ascent-make-aggregate-value
  gerbil-ascent-check-owned-aggregate-value
  gerbil-ascent-make-relation-value
  gerbil-ascent-check-owned-relation-value
  gerbil-ascent-make-program-value
  gerbil-ascent-check-source-handles
  gerbil-ascent-projection-tree-current?
  gerbil-ascent-check-projection-program
  gerbil-ascent-relation-with-rows
  gerbil-ascent-relation-with-role
  gerbil-ascent-rule-with-origin
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

;;; Declarative metadata leaves all original semantic fields inherited. Reuse
;;; the existing factory-issued shape discipline, never a validation result.
;;; Caller objects and ancestor edits retain the ordinary complete checks.
;; gerbil-ascent-relation-with-role
;; : (forall (r m) (-> r m r))
;; : (-> Relation RelationRole Relation)
;; | doc m%
;;     Attach declaration metadata without changing inherited relation fields.
;;     Boundary: only an unchanged factory-issued parent can issue a child shape.
;;     Invariant: the child is never a cached successful admission.
;;
;;     # Examples
;;
;;     ```scheme
;;     (.ref (gerbil-ascent-relation-with-role relation 'input) 'checked-role)
;;     ;; => input
;;     ```
;;   %
(def (gerbil-ascent-relation-with-role relation role)
  (let (value (.o (:: @ relation) checked-role: role))
    (if (declared-value-shape? 'relation relation)
      (remember-value-shape! 'relation value) value)))
;; gerbil-ascent-rule-with-origin
;; : (forall (r o) (-> r o r))
;; : (-> Rule DetachedOrigin Rule)
;; | doc m%
;;     Preserve a rule's semantic fields while attaching diagnostic reader data.
;;     Boundary: checked admission separately validates and detaches this data.
;;     Invariant: source metadata grants no validation or source-update authority.
;;
;;     # Examples
;;
;;     ```scheme
;;     (.ref (gerbil-ascent-rule-with-origin rule #f) 'source-origin)
;;     ;; => #f
;;     ```
;;   %
(def (gerbil-ascent-rule-with-origin rule origin)
  (let (value (.o (:: @ rule) source-origin: origin))
    (if (declared-value-shape? 'rule rule)
      (remember-value-shape! 'rule value) value)))

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

;;; The factory owns the selected fields, not an admission receipt. A scalar
;;; aggregate with owned terms can use pure field checks only while all six
;;; public classifier protocols retain their original identities. Other clauses
;;; and every changed/failed view retain the original ordered public union.
;; BEGIN GENERATED OWNED AGGREGATE VALUE
(def +aggregate-slots+
  '(ascent-clause-kind variable relation terms variables aggregate checked-operator output-pattern .plan))
(def aggregate-value-current?
  (canonical-value-check-current? GerbilAscentAggregateContract +aggregate-slots+))
(def aggregate-predecessors-current?
  (let (checks
    (map (lambda (entry) (canonical-value-check-current? (car entry) (cdr entry)))
      (list (cons GerbilAscentAtomContract '(ascent-clause-kind relation terms .plan))
            (cons GerbilAscentGuardContract '(ascent-clause-kind variables predicate checked-operator .plan))
            (cons GerbilAscentGeneratorContract '(ascent-clause-kind variable variables generate .plan))
            (cons GerbilAscentBindingContract '(ascent-clause-kind variable variables checked-operator compute .plan))
            (cons GerbilAscentNegationContract '(ascent-clause-kind relation terms .plan)))))
    (lambda () (andmap (lambda (current?) (current?)) checks))))
(def +aggregate-value+
  (.cc ObjectContract. identity: 'ascent/aggregate-value
       required-prototype: (.ref GerbilAscentAggregateContract 'proto)
       extra-fields: 'delegate constraints: (list Any)
       responsibilities:
       (.o ascent-clause-kind: (.cc Type. .element?: (cut clause-kind? 'aggregate <>))
           variable: (.cc Type. .element?: symbol?)
           relation: (.cc Type. .element?: symbol?)
           terms: (.cc Type. .element?: terms-value?)
           variables: (.cc Type. .element?: (lambda (v) (and (list? v) (andmap symbol? v))))
           aggregate: (.cc Type. .element?: procedure?)
           checked-operator: (.cc Type. .element?: (lambda (v) (or (not v) (vector? v))))
           output-pattern: (.cc Type. .element?: not)
           .plan: (.cc Type. .element?: procedure?))))
(def (owned-aggregate-fields? value)
  (and (declared-value-shape? 'aggregate value) (term-value-current?)
       (symbol? (.ref value 'variable)) (not (.ref value 'output-pattern))
       (let (terms (.ref value 'terms))
         (and (list? terms) (andmap (cut declared-value-shape? 'term <>) terms)))))
(def (gerbil-ascent-make-aggregate-value prototype output-value relation-name atom-terms input-variables aggregate-procedure matcher operator-descriptor lower)
  (remember-value-shape! 'aggregate
    (.o (:: self prototype) ascent-clause-kind: 'aggregate variable: output-value
        relation: relation-name terms: atom-terms variables: input-variables aggregate: aggregate-procedure
        output-pattern: matcher checked-operator: operator-descriptor
        (.plan (lambda (plan bound) (lower self plan bound))))))
(def (gerbil-ascent-check-owned-aggregate-value value)
  (if (and (owned-aggregate-fields? value) (aggregate-value-current?)
           (element? +aggregate-value+ value)) value
      (validate GerbilAscentAggregateContract value)))
(def (public-clause-value? clause)
  (or (atom-value? clause)
      (element? GerbilAscentGuardContract clause)
      (element? GerbilAscentGeneratorContract clause)
      (element? GerbilAscentBindingContract clause)
      (element? GerbilAscentNegationContract clause)
      (element? GerbilAscentAggregateContract clause)))
(def (clause-value? clause)
  (or (and (owned-aggregate-fields? clause) (aggregate-predecessors-current?)
           (aggregate-value-current?) (element? +aggregate-value+ clause))
      (public-clause-value? clause)))
;; END GENERATED OWNED AGGREGATE VALUE

(def +clauses+
  (slot-contract 'ascent/clauses
                 (lambda (value) (and (list? value) (andmap clause-value? value)))))
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
       (.o heads: (.cc Type. .element?: (lambda (head-atoms)
             (and (pair? head-atoms) (list? head-atoms) (andmap atom-value? head-atoms))))
           body: (.cc Type. .element?: (lambda (body-atoms)
             (and (list? body-atoms) (andmap atom-value? body-atoms)))))))
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

;;; POO slots memoize their first value. Advance the declaration cursor only
;;; as far as each request needs, retaining the original first-force order.
;;; This index belongs to one construction; later calls inspect fresh objects.
;; : (forall (a) (-> [a] (-> Symbol Boolean)))
;; : (-> RelationDeclarations DeclaredNamePredicate)
(def (declared-name-membership relations)
  (let ((remaining relations) (names (make-hash-table-eq)))
    (lambda (name)
      (or (hash-get names name)
          (let scan ()
            (and (not (null? remaining))
                 (let (found (.ref (car remaining) 'name))
                   (set! remaining (cdr remaining))
                   (hash-put! names found #t)
                   (or (eq? found name) (scan)))))))))

;; gerbil-ascent-check-source-handles
;; : (forall (r) (-> [r] [Symbol] [Symbol]))
;; : (-> RelationDeclarations SourceHandles DetachedSourceHandles)
;; | doc m%
;;     Validate and detach a finite ordered list of unique declared names.
;;     Relation names are read lazily in first-request order; caller getters
;;     remain observable and no successful validation is cached across calls.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-check-source-handles '() '())
;;     ;; => '()
;;     ```
;;   %
(def (gerbil-ascent-check-source-handles relations source-handle-values)
  (unless (list? source-handle-values)
    (error "invalid ASCENT source handles" source-handle-values))
  (def seen (make-hash-table-eq))
  (def declared? (declared-name-membership relations))
  (let loop ((remaining source-handle-values) (copied []))
    (if (null? remaining)
      (reverse copied)
      (let (name (car remaining))
        (unless (and (symbol? name)
                     (not (hash-get seen name))
                     (declared? name))
          (error "invalid or duplicate ASCENT source handle" name))
        (hash-put! seen name #t)
        (loop (cdr remaining) (cons name copied))))))

;;; Private projection objects may be reused; successful checks never are.
;;; Foreign trees, callback-bearing protocols and edited factories keep the
;;; original fresh-constructor path, including its getter/exception ordering.
(def projection-program-current?
  (canonical-value-check-current? GerbilAscentProgramContract
    '(relations rules source-handles max-input-facts max-derived-facts max-output-facts)))

(def (gerbil-ascent-make-program-value prototype relation-values rule-values handles input-limit derived-limit output-limit)
  (remember-value-shape! 'program
    (.o (:: @ prototype) relations: relation-values rules: rule-values
        source-handles: (gerbil-ascent-check-source-handles relation-values handles)
        max-input-facts: input-limit
        max-derived-facts: derived-limit max-output-facts: output-limit)))

(def (gerbil-ascent-projection-tree-current? program)
  (and (declared-value-shape? 'program program)
       (projection-program-current?) (relation-protocol-current?) (relation-metadata-current?)
       (rule-value-current?) (atom-value-check-current?) (term-value-current?)
       (aggregate-value-current?) (aggregate-predecessors-current?)
       (let ((relations (.ref program 'relations)) (rules (.ref program 'rules))
             (handles (.ref program 'source-handles)))
         (and (list? relations) (andmap owned-canonical-relation? relations)
              (list? handles) (andmap symbol? handles)
              (list? rules)
              (andmap (lambda (rule)
                (and (declared-value-shape? 'rule rule)
                     (let ((heads (.ref rule 'heads)) (body (.ref rule 'body)))
                       (and (pair? heads) (list? heads) (andmap owned-atom-fields? heads)
                            (list? body)
                            (andmap (lambda (clause)
                              (or (owned-atom-fields? clause) (owned-aggregate-fields? clause))) body))))) rules)))))

(def (gerbil-ascent-check-projection-program program)
  (validate GerbilAscentProgramContract program))

;;; Session operations are the only mutable public boundary. A run returns an
;;; immutable result snapshot even when later appends extend the session.
;; Prototype identity outlives the descriptor's lazily materialized slot cache.
;; Rematerialization must not invalidate already published native Sessions.
(def +session-prototype+ (.o))
;;; Boundary: public Session values expose only admitted mutable operations.
;;; Invariant: this stable prototype survives descriptor cache rematerialization.
(define-type (GerbilAscentSessionContract @ YuanxuObjectContract.)
  identity: 'ascent/session
  proto: +session-prototype+
  responsibilities:
  (.o .append-source!: +procedure+
      .source-replacement: +procedure+
      .run: +procedure+))

;; This factory owns all field getters. It checks every mandatory procedure on
;; each call, while explicit public/contextual admission keeps its full receipts.
(def +session-value+
  (.cc ObjectContract. identity: 'ascent/session-value
       required-prototype: +session-prototype+
       extra-fields: 'delegate constraints: (list Any)
       responsibilities:
       (.o .append-source!: (.cc Type. .element?: procedure?)
           .source-replacement: (.cc Type. .element?: procedure?)
           .run: (.cc Type. .element?: procedure?))))

(def session-metadata-current?
  (canonical-metadata-current? GerbilAscentSessionContract '(.append-source! .source-replacement .run)))

(def session-protocol-current?
  (canonical-validation-current? GerbilAscentSessionContract '(.append-source! .source-replacement .run)))

(def (gerbil-ascent-make-session-value append! replace! replace-all! run! timeout!)
  (let (value (.o (:: @ (.ref GerbilAscentSessionContract 'proto))
                .append-source!: append! .source-replacement: replace!
                .source-replacements: replace-all! .run: run! .run-timeout: timeout!))
    (if (and (session-metadata-current?) (session-protocol-current?)
             (element? +session-value+ value))
      value
      (validate GerbilAscentSessionContract value))))

;;; The Module publishes these existing native operations. Engine state and
;;; candidate values retain their own contracts; publication is not execution.
(def ProgramScopeContract
  (.cc YuanxuContract.
    identity: 'ascent/program-scope
    proto: (.o)
    value-contract:
    (Record
      relation: (list +procedure+)
      program: (list +procedure+)
      evaluate: (list +procedure+)
      open-session: (list +procedure+)
      solve: (list +procedure+))))
