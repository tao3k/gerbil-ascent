;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Public POO declarations for ASCENT rules. No table state lives
;;; in these objects; each evaluation owns its own relation storage.
(import (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop .defgeneric validate)
        (only-in :gerbil-ascent/table/provider
                 gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage
                 gerbil-ascent-set-storage-provider)
        (only-in "types.ss"
                 gerbil-ascent-make-term-value gerbil-ascent-make-atom-value
                 gerbil-ascent-check-owned-term-value gerbil-ascent-check-owned-atom-value
                 gerbil-ascent-make-rule-value gerbil-ascent-check-owned-rule-value
                 gerbil-ascent-make-program-value gerbil-ascent-check-source-handles
                 gerbil-ascent-make-aggregate-value gerbil-ascent-check-owned-aggregate-value
                 gerbil-ascent-make-relation-value gerbil-ascent-check-owned-relation-value
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
                 GerbilAscentProgramContract))

(export gerbil-ascent-relation
        gerbil-ascent-lattice
        gerbil-ascent-variable
        gerbil-ascent-wildcard
        gerbil-ascent-literal
        gerbil-ascent-expression
        gerbil-ascent-pattern
        gerbil-ascent-atom
        gerbil-ascent-guard
        gerbil-ascent-generator
        gerbil-ascent-binding
        gerbil-ascent-negation
        gerbil-ascent-aggregate
        gerbil-ascent-clause-plan
        gerbil-ascent-bound-membership
        gerbil-ascent-rule
        gerbil-ascent-fragment
        gerbil-ascent-program gerbil-ascent-construct-inert-program
        gerbil-ascent-construct-inert-fragment)

;;; A private inert construction flow has no supplied procedures or escaping
;;; children. Its root contract recursively checks the complete POO object tree.
;;; Ordinary public constructors keep immediate validation. No validation result
;;; is cached across calls, and dynamic extent restores checks after failure.
(def current-declaration-check (make-parameter validate))
;; BEGIN GENERATED OWNED DECLARATION CHECK
(def (declaration-check contract value)
  (let (check (current-declaration-check))
    (cond
      ((not (eq? check validate)) (check contract value))
      ((eq? contract GerbilAscentTermContract) (gerbil-ascent-check-owned-term-value value))
      ((eq? contract GerbilAscentAtomContract) (gerbil-ascent-check-owned-atom-value value))
      ((eq? contract GerbilAscentRuleContract) (gerbil-ascent-check-owned-rule-value value))
      ((eq? contract GerbilAscentAggregateContract) (gerbil-ascent-check-owned-aggregate-value value))
      (else (check contract value)))))
;; END GENERATED OWNED DECLARATION CHECK

;;; Only canonical, callback-free producers may borrow this construction extent.
;;; The receiver runs after ordinary checks have been restored, including throws.
;; : (forall (a r) (-> (-> a) (-> a r) r))
;; : (-> InertDeclarationConstructor CheckedRootReceiver ValidatedRoot)
;; BEGIN GENERATED DSL-ROOT
(def (receive-inert-declarations construct receive)
  (call-with-values
   (lambda ()
     (parameterize ((current-declaration-check (lambda (_contract value) value)))
       (construct)))
   receive))

;;; Publish through the public root descriptor once, after restoring ordinary
;;; constructor checks. No responsibility override or Term result cache escapes.
;; : (forall (p a) (-> (-> (Values p a)) (Values p a)))
;; : (-> InertProgramConstructor (Values ValidatedProgram OutputHandle))
(def (gerbil-ascent-construct-inert-program construct)
  (receive-inert-declarations construct
   (case-lambda
     ((program) (validate GerbilAscentProgramContract program))
     ((program output)
      (let (checked (validate GerbilAscentProgramContract program))
        (values checked output))))))

;; END GENERATED DSL-ROOT

;; : (forall (f) (-> (-> f) f))
;; : (-> InertFragmentConstructor ValidatedFragment)
(def (gerbil-ascent-construct-inert-fragment construct)
  (receive-inert-declarations construct
    (lambda (fragment) (validate GerbilAscentFragmentContract fragment))))

(def Relation. (.ref GerbilAscentRelationContract 'proto))
(def Lattice. (.ref GerbilAscentLatticeContract 'proto))
(def Term. (.ref GerbilAscentTermContract 'proto))
(def Atom. (.ref GerbilAscentAtomContract 'proto))
(def Guard. (.ref GerbilAscentGuardContract 'proto))
(def Generator. (.ref GerbilAscentGeneratorContract 'proto))
(def Binding. (.ref GerbilAscentBindingContract 'proto))
(def Negation. (.ref GerbilAscentNegationContract 'proto))
(def Aggregate. (.ref GerbilAscentAggregateContract 'proto))
(def Rule. (.ref GerbilAscentRuleContract 'proto))
(def Fragment. (.ref GerbilAscentFragmentContract 'proto))
(def Program. (.ref GerbilAscentProgramContract 'proto))

;;; Clause lowering has one open receiver axis. The evaluator consumes the
;;; resulting private plan without dispatching through POO in the row loop.
(.defgeneric (gerbil-ascent-clause-plan clause atom-plan bound)
  slot: .plan)

;; : (-> (List Symbol) NameIndex)
(def (name-index names)
  (let (index (make-hash-table-eq))
    (for-each (cut hash-put! index <> #t) names)
    index))

;; : (forall (a) (-> (List a) Boolean))
(def (wide-scope? names)
  ;; A bounded predicate stops at the 32nd pair without materializing a list.
  (def (enough? remaining left)
    (and (pair? remaining)
         (or (fx= left 1) (enough? (cdr remaining) (fx- left 1)))))
  (enough? names 32))

;;; Admission-local lookup: small scopes retain list membership. Repeated
;;; reads amortize one symbol index; its snapshot never changes the bound list
;;; passed to an open clause planner, and never survives in an execution plan.
;; gerbil-ascent-bound-membership
;;   : (forall (name) (-> (List name) (-> name Boolean)))
;;   : (-> BoundNames BoundPredicate)
;;   | doc m%
;;       Resolve admitted names by identity in a private scope snapshot.
;;       Repeated queries share one lazily constructed index.
;;
;;       # Examples
;;
;;       ```scheme
;;       ((gerbil-ascent-bound-membership '(x y)) 'x)
;;       ;; => #t
;;       ```
;;     %
(def (gerbil-ascent-bound-membership names)
  (if (not (wide-scope? names))
    (lambda (name) (and (memq name names) #t))
    (let ((index #f) (reads 0))
      (lambda (name)
        (if index
          (hash-get index name)
          (begin
            (set! reads (fx+ reads 1))
            (if (fx= reads 32)
              (begin (set! index (name-index names)) (hash-get index name))
              (and (memq name names) #t))))))))

(def (require-bound names bound?)
  (for-each
   (lambda (name)
     (unless (bound? name)
       (error "unbound ASCENT clause variable" name)))
   names))

(def (pattern-outputs term)
  (and (eq? (car term) 'pattern)
       (vector-ref (cdr term) 0)))

(def (indexed-atom plan bound)
  (let* ((wide? (wide-scope? (vector-ref plan 1)))
         (prior? (gerbil-ascent-bound-membership bound))
         (seen-bound (if wide? (name-index bound) bound)))
    (def (seen? name)
      (if wide? (hash-get seen-bound name) (memq name seen-bound)))
    (let loop ((terms (vector-ref plan 1)) (column 0)
               (columns []) (bindings []) (key-terms []))
      (if (null? terms)
        (vector (vector-ref plan 0) (vector-ref plan 1)
                (reverse columns) (reverse bindings) (reverse key-terms))
        (let* ((term (car terms))
               (kind (car term))
               (inputs (and (eq? kind 'expression) (vector-ref (cdr term) 0))))
          (when inputs (require-bound inputs seen?))
          (let* ((indexed?
                  (or (eq? kind 'literal)
                      (and (eq? kind 'variable) (prior? (cdr term)))
                      (and inputs (andmap prior? inputs))))
                 ;; Read freshness before extending the row-local scope.
                 ;; Same-atom repeats and pattern names still compare values.
                 (binding
                  (if (and (eq? kind 'variable) (not (seen? (cdr term))))
                    (cons 'fresh-variable (cdr term)) term)))
            (case kind
              ((variable)
               (if wide?
                 (hash-put! seen-bound (cdr term) #t)
                 (set! seen-bound (cons (cdr term) seen-bound))))
              ((pattern)
               (if wide?
                 (for-each (cut hash-put! seen-bound <> #t) (pattern-outputs term))
                 (set! seen-bound (append (pattern-outputs term) seen-bound)))))
            ;; The result contains descriptors only. Scratch indexes and their
            ;; lookup closures are never retained by the immutable plan.
            (loop (cdr terms) (+ column 1)
                  (if indexed? (cons column columns) columns)
                  (cons binding bindings)
                  (if indexed? (cons term key-terms) key-terms))))))))

(def (atom-clause-plan clause atom-plan bound)
  (let* ((plan (indexed-atom (atom-plan clause) bound))
         (next-bound
          (foldl (lambda (term prior)
                   (cond
                    ((eq? (car term) 'variable)
                     (cons (cdr term) prior))
                    ((eq? (car term) 'pattern)
                     (let loop ((outputs (pattern-outputs term))
                                (next prior))
                       (if (null? outputs)
                         next
                         (begin
                           (when (memq (car outputs) next)
                             (error "ASCENT pattern variable already bound"
                                    (car outputs)))
                           (loop (cdr outputs)
                                 (cons (car outputs) next))))))
                    (else prior)))
                 bound (vector-ref plan 1))))
    (vector (vector 'atom plan) next-bound 1)))

(def (negation-clause-plan clause atom-plan bound)
  (let ((plan (indexed-atom (atom-plan clause) bound))
        (bound? (gerbil-ascent-bound-membership bound)))
    (for-each
     (lambda (term)
       (when (eq? (car term) 'pattern)
         (error "ASCENT pattern cannot bind in negation"))
       (when (and (eq? (car term) 'variable)
                  (not (bound? (cdr term))))
         (error "unsafe ASCENT negation variable" (cdr term))))
     (vector-ref plan 1))
    (vector (vector 'negation plan) bound 0)))

(def (computed-clause-plan clause kind function-slot bound)
  (let* ((inputs (.ref clause 'variables))
         (name (.ref clause 'variable))
         (names (if (and (eq? kind 'generator) (list? name))
                  name (list name))))
    (require-bound inputs (gerbil-ascent-bound-membership bound))
    (let (known (and (wide-scope? names) (name-index bound)))
      (let loop ((remaining names) (next-bound bound))
        (if (null? remaining)
          (vector
           (vector kind
                   (if (list? name)
                     (map (lambda (output) (cons 'variable output)) name)
                     name)
                   inputs (.ref clause function-slot))
           next-bound 0)
          (begin
            (when (if known (hash-get known (car remaining))
                      (memq (car remaining) next-bound))
              (error "ASCENT computed variable already bound" (car remaining)))
            (when known (hash-put! known (car remaining) #t))
            (loop (cdr remaining) (cons (car remaining) next-bound))))))))

(def (aggregate-clause-plan clause atom-plan bound)
  (let* ((plan (indexed-atom (atom-plan clause) bound))
         (name (.ref clause 'variable))
         (names (if (list? name) name (list name)))
         (inputs (.ref clause 'variables))
         (terms (vector-ref plan 1)))
    (when (ormap pattern-outputs terms)
      (error "ASCENT pattern cannot bind in aggregate"))
    (let (known (and (wide-scope? names) (name-index bound)))
      (let loop ((remaining names) (next-bound bound))
        (unless (null? remaining)
          (when (if known (hash-get known (car remaining))
                    (memq (car remaining) next-bound))
            (error "ASCENT aggregate variable already bound" (car remaining)))
          (when known (hash-put! known (car remaining) #t))
          (loop (cdr remaining) (cons (car remaining) next-bound)))))
    ;; Atom membership has no callbacks. Build only for a wide input query;
    ;; output and pattern diagnostics above retain their original priority.
    (let (variables
          (and (wide-scope? inputs)
               (name-index
                (filter-map (lambda (term)
                              (and (eq? (car term) 'variable) (cdr term)))
                            terms))))
      (for-each
       (lambda (input)
         (unless (if variables (hash-get variables input)
                   (ormap (lambda (term)
                            (and (eq? (car term) 'variable)
                                 (eq? (cdr term) input))) terms))
           (error "ASCENT aggregate input absent from atom" input)))
       inputs))
    (vector (vector 'aggregate plan name inputs (.ref clause 'aggregate)
                    (.ref clause 'output-pattern))
            (append names bound) 0)))

(def (gerbil-ascent-relation relation-name column-count source-rows
                             (provider-value gerbil-ascent-hash-index-provider)
                             (storage-value gerbil-ascent-set-storage-provider)
                             (field-predicates-value [])
                             (domain-descriptor #f))
  (unless (and (symbol? relation-name)
               (exact-integer? column-count) (<= 0 column-count)
               (list? source-rows)
               (list? field-predicates-value)
               (or (null? field-predicates-value)
                   (= (length field-predicates-value) column-count))
               (andmap procedure? field-predicates-value))
    (error "invalid ASCENT relation declaration" relation-name column-count))
  (for-each
   (lambda (row)
     (unless (and (list? row) (= (length row) column-count))
       (error "invalid ASCENT relation row" relation-name row column-count))
     (when (pair? field-predicates-value)
       (for-each
        (lambda (predicate value)
          (unless (predicate value)
            (error "ASCENT relation source field type mismatch"
                   relation-name row)))
        field-predicates-value row)))
   source-rows)
  (let ((value (gerbil-ascent-make-relation-value Relation. relation-name column-count source-rows
                 field-predicates-value domain-descriptor provider-value storage-value))
        (check (current-declaration-check)))
    (if (eq? check validate) (gerbil-ascent-check-owned-relation-value value)
        (check GerbilAscentRelationContract value))))

(def (gerbil-ascent-lattice relation-name column-count source-rows
                            join-procedure
                            (provider-value gerbil-ascent-hash-index-provider)
                            (field-predicates-value [])
                            (operator-descriptor #f)
                            (domain-descriptor #f))
  (unless (and (symbol? relation-name)
               (exact-integer? column-count) (> column-count 0)
               (list? source-rows) (procedure? join-procedure)
               (list? field-predicates-value)
               (or (null? field-predicates-value)
                   (= (length field-predicates-value) column-count))
               (andmap procedure? field-predicates-value))
    (error "invalid ASCENT lattice declaration" relation-name column-count))
  (for-each
   (lambda (row)
     (unless (and (list? row) (= (length row) column-count))
       (error "invalid ASCENT lattice row" relation-name row column-count))
     (when (pair? field-predicates-value)
       (for-each
        (lambda (predicate value)
          (unless (predicate value)
            (error "ASCENT lattice source field type mismatch"
                   relation-name row)))
        field-predicates-value row)))
   source-rows)
  (declaration-check GerbilAscentLatticeContract
            (.o (:: @ Lattice.)
                name: relation-name arity: column-count rows: source-rows
                field-predicates: field-predicates-value
                checked-domain: domain-descriptor
                storage-kind: 'lattice join: join-procedure
                checked-operator: operator-descriptor
                index-provider: provider-value)))

(def (gerbil-ascent-variable name)
  (unless (symbol? name) (error "ASCENT variable name must be a symbol" name))
  (declaration-check GerbilAscentTermContract
            (gerbil-ascent-make-term-value Term. 'variable name)))

(def (gerbil-ascent-wildcard)
  (declaration-check GerbilAscentTermContract
            (gerbil-ascent-make-term-value Term. 'wildcard #f)))

(def (gerbil-ascent-literal literal-value)
  (declaration-check GerbilAscentTermContract
            (gerbil-ascent-make-term-value Term. 'literal literal-value)))

(def (gerbil-ascent-expression input-variables compute)
  (unless (and (list? input-variables)
               (andmap symbol? input-variables)
               (procedure? compute))
    (error "invalid ASCENT head expression" input-variables compute))
  (declaration-check GerbilAscentTermContract
            (gerbil-ascent-make-term-value Term. 'expression (vector input-variables compute))))

(def (gerbil-ascent-pattern output-variables matcher)
  (unless (and (list? output-variables)
               (andmap symbol? output-variables)
               (procedure? matcher))
    (error "invalid ASCENT pattern" output-variables matcher))
  (declaration-check GerbilAscentTermContract
            (gerbil-ascent-make-term-value Term. 'pattern (vector output-variables matcher))))

(def (gerbil-ascent-atom relation-name atom-terms)
  (declaration-check GerbilAscentAtomContract
    (gerbil-ascent-make-atom-value Atom. relation-name atom-terms atom-clause-plan)))

(def (gerbil-ascent-guard input-variables guard-procedure
                          (operator-descriptor #f))
  (declaration-check GerbilAscentGuardContract
            (.o (:: self Guard.) ascent-clause-kind: 'guard
                variables: input-variables
                predicate: guard-procedure
                checked-operator: operator-descriptor
                (.plan (lambda (_atom-plan bound)
                         (require-bound (.ref self 'variables)
                                        (gerbil-ascent-bound-membership bound))
                         (vector (vector 'guard (.ref self 'variables)
                                         (.ref self 'predicate))
                                 bound 0))))))

(def (gerbil-ascent-generator output-variable input-variables
                              generator-procedure)
  (declaration-check GerbilAscentGeneratorContract
            (.o (:: self Generator.) ascent-clause-kind: 'generator
                variable: output-variable
                variables: input-variables generate: generator-procedure
                (.plan (lambda (_atom-plan bound)
                         (computed-clause-plan self 'generator
                                               'generate bound))))))

(def (gerbil-ascent-binding output-variable input-variables
                            binding-procedure (operator-descriptor #f))
  (declaration-check GerbilAscentBindingContract
            (.o (:: self Binding.) ascent-clause-kind: 'binding
                variable: output-variable variables: input-variables
                compute: binding-procedure
                checked-operator: operator-descriptor
                (.plan (lambda (_atom-plan bound)
                         (computed-clause-plan self 'binding
                                               'compute bound))))))

(def (gerbil-ascent-negation relation-name atom-terms)
  (declaration-check GerbilAscentNegationContract
            (.o (:: self Negation.) ascent-clause-kind: 'negation
                relation: relation-name terms: atom-terms
                (.plan (lambda (atom-plan bound)
                         (negation-clause-plan self atom-plan bound))))))

;; BEGIN GENERATED AGGREGATE CONSTRUCTOR
(def (gerbil-ascent-aggregate output-variable relation-name atom-terms
                              value-variables aggregate-procedure
                              (matcher #f) (operator-descriptor #f))
  (unless (or (and (symbol? output-variable) (not matcher))
              (and (pair? output-variable) (list? output-variable)
                   (andmap symbol? output-variable)
                   (procedure? matcher)))
    (error "invalid ASCENT aggregate output" output-variable matcher))
  (declaration-check GerbilAscentAggregateContract
    (gerbil-ascent-make-aggregate-value Aggregate. output-variable relation-name atom-terms
      value-variables aggregate-procedure matcher operator-descriptor aggregate-clause-plan)))

;; END GENERATED AGGREGATE CONSTRUCTOR

(def (gerbil-ascent-rule head-atoms body-atoms)
  (declaration-check GerbilAscentRuleContract
            (gerbil-ascent-make-rule-value Rule. head-atoms body-atoms)))

;;; Copy the signature before closure capture so a caller cannot rewrite an
;;; exported handle through the alist passed to this constructor.
(def (fragment-export-resolver export-values)
  (unless (list? export-values)
    (error "invalid ASCENT fragment exports" export-values))
  (let (entries (make-hash-table-eq))
    (for-each
      (lambda (entry)
        (unless (and (pair? entry)
                     (symbol? (car entry))
                     (symbol? (cdr entry))
                     (not (hash-get entries (car entry))))
          (error "invalid or duplicate ASCENT fragment export" entry))
        ;; Both symbols are immutable. Retain their values, never the caller's
        ;; association spine, and freeze the table before resolver publication.
        (hash-put! entries (car entry) (cdr entry))) export-values)
    (lambda (label)
      (or (hash-get entries label)
          (error "unknown relational fragment export" label)))))

(def (gerbil-ascent-fragment relation-values rule-values
                             (export-values []) (source-handle-values []))
  (declaration-check GerbilAscentFragmentContract
            (.o (:: @ Fragment.)
                relations: relation-values rules: rule-values
                exports: (fragment-export-resolver export-values)
                source-handles:
                (gerbil-ascent-check-source-handles relation-values
                                        source-handle-values))))

(def (gerbil-ascent-program declared-relations declared-rules
                                     (input-fact-limit +inf.0) (derived-fact-limit +inf.0)
                                     (output-fact-limit +inf.0)
                                     (source-handle-values []))
  (declaration-check GerbilAscentProgramContract
    (gerbil-ascent-make-program-value Program. declared-relations declared-rules
      source-handle-values
      input-fact-limit derived-fact-limit output-fact-limit)))
