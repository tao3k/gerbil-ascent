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
        (only-in :gerbil-ascent/program/types
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
        gerbil-ascent-program)

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
  (validate GerbilAscentRelationContract
            (.o (:: @ Relation.)
                name: relation-name arity: column-count rows: source-rows
                field-predicates: field-predicates-value
                checked-domain: domain-descriptor
                storage-kind: 'relation index-provider: provider-value
                storage-provider: storage-value)))

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
  (validate GerbilAscentLatticeContract
            (.o (:: @ Lattice.)
                name: relation-name arity: column-count rows: source-rows
                field-predicates: field-predicates-value
                checked-domain: domain-descriptor
                storage-kind: 'lattice join: join-procedure
                checked-operator: operator-descriptor
                index-provider: provider-value)))

(def (gerbil-ascent-variable name)
  (unless (symbol? name) (error "ASCENT variable name must be a symbol" name))
  (validate GerbilAscentTermContract
            (.o (:: @ Term.) kind: 'variable value: name)))

(def (gerbil-ascent-wildcard)
  (validate GerbilAscentTermContract
            (.o (:: @ Term.) kind: 'wildcard value: #f)))

(def (gerbil-ascent-literal literal-value)
  (validate GerbilAscentTermContract
            (.o (:: @ Term.) kind: 'literal value: literal-value)))

(def (gerbil-ascent-expression input-variables compute)
  (unless (and (list? input-variables)
               (andmap symbol? input-variables)
               (procedure? compute))
    (error "invalid ASCENT head expression" input-variables compute))
  (validate GerbilAscentTermContract
            (.o (:: @ Term.) kind: 'expression
                value: (vector input-variables compute))))

(def (gerbil-ascent-pattern output-variables matcher)
  (unless (and (list? output-variables)
               (andmap symbol? output-variables)
               (procedure? matcher))
    (error "invalid ASCENT pattern" output-variables matcher))
  (validate GerbilAscentTermContract
            (.o (:: @ Term.) kind: 'pattern
                value: (vector output-variables matcher))))

(def (gerbil-ascent-atom relation-name atom-terms)
  (validate GerbilAscentAtomContract
            (.o (:: self Atom.) ascent-clause-kind: 'atom
                relation: relation-name terms: atom-terms
                (.plan (lambda (atom-plan bound)
                         (atom-clause-plan self atom-plan bound))))))

(def (gerbil-ascent-guard input-variables guard-procedure
                          (operator-descriptor #f))
  (validate GerbilAscentGuardContract
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
  (validate GerbilAscentGeneratorContract
            (.o (:: self Generator.) ascent-clause-kind: 'generator
                variable: output-variable
                variables: input-variables generate: generator-procedure
                (.plan (lambda (_atom-plan bound)
                         (computed-clause-plan self 'generator
                                               'generate bound))))))

(def (gerbil-ascent-binding output-variable input-variables
                            binding-procedure (operator-descriptor #f))
  (validate GerbilAscentBindingContract
            (.o (:: self Binding.) ascent-clause-kind: 'binding
                variable: output-variable variables: input-variables
                compute: binding-procedure
                checked-operator: operator-descriptor
                (.plan (lambda (_atom-plan bound)
                         (computed-clause-plan self 'binding
                                               'compute bound))))))

(def (gerbil-ascent-negation relation-name atom-terms)
  (validate GerbilAscentNegationContract
            (.o (:: self Negation.) ascent-clause-kind: 'negation
                relation: relation-name terms: atom-terms
                (.plan (lambda (atom-plan bound)
                         (negation-clause-plan self atom-plan bound))))))

(def (gerbil-ascent-aggregate output-variable relation-name atom-terms
                              value-variables aggregate-procedure
                              (matcher #f) (operator-descriptor #f))
  (unless (or (and (symbol? output-variable) (not matcher))
              (and (pair? output-variable) (list? output-variable)
                   (andmap symbol? output-variable)
                   (procedure? matcher)))
    (error "invalid ASCENT aggregate output" output-variable matcher))
  (validate GerbilAscentAggregateContract
            (.o (:: self Aggregate.) ascent-clause-kind: 'aggregate
                variable: output-variable relation: relation-name
                terms: atom-terms variables: value-variables
                aggregate: aggregate-procedure output-pattern: matcher
                checked-operator: operator-descriptor
                (.plan (lambda (atom-plan bound)
                         (aggregate-clause-plan self atom-plan bound))))))

(def (gerbil-ascent-rule head-atoms body-atoms)
  (validate GerbilAscentRuleContract
            (.o (:: @ Rule.) heads: head-atoms body: body-atoms)))

;;; Copy the signature before closure capture so a caller cannot rewrite an
;;; exported handle through the alist passed to this constructor.
(def (fragment-export-resolver export-values)
  (unless (list? export-values)
    (error "invalid ASCENT fragment exports" export-values))
  (let loop ((remaining export-values) (seen []) (copied []))
    (if (null? remaining)
      (let (entries (reverse copied))
        (lambda (label)
          (let (entry (assq label entries))
            (unless entry
              (error "unknown relational fragment export" label))
            (cdr entry))))
      (let (entry (car remaining))
        (unless (and (pair? entry)
                     (symbol? (car entry))
                     (symbol? (cdr entry))
                     (not (memq (car entry) seen)))
          (error "invalid or duplicate ASCENT fragment export" entry))
        (loop (cdr remaining)
              (cons (car entry) seen)
              (cons (cons (car entry) (cdr entry)) copied))))))

(def (checked-source-handles relations source-handle-values)
  (unless (list? source-handle-values)
    (error "invalid ASCENT source handles" source-handle-values))
  (let loop ((remaining source-handle-values) (seen []))
    (if (null? remaining)
      (reverse seen)
      (let (name (car remaining))
        (unless (and (symbol? name)
                     (not (memq name seen))
                     (ormap (lambda (relation)
                              (eq? (.ref relation 'name) name))
                            relations))
          (error "invalid or duplicate ASCENT source handle" name))
        (loop (cdr remaining) (cons name seen))))))

(def (gerbil-ascent-fragment relation-values rule-values
                             (export-values []) (source-handle-values []))
  (validate GerbilAscentFragmentContract
            (.o (:: @ Fragment.)
                relations: relation-values rules: rule-values
                exports: (fragment-export-resolver export-values)
                source-handles:
                (checked-source-handles relation-values
                                        source-handle-values))))

(def (gerbil-ascent-program declared-relations declared-rules
                                     input-fact-limit derived-fact-limit
                                     output-fact-limit
                                     (source-handle-values []))
  (validate GerbilAscentProgramContract
            (.o (:: @ Program.)
                relations: declared-relations rules: declared-rules
                source-handles:
                (checked-source-handles declared-relations
                                        source-handle-values)
                max-input-facts: input-fact-limit
                max-derived-facts: derived-fact-limit
                max-output-facts: output-fact-limit)))
