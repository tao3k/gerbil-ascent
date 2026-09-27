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
                 GerbilAscentProgramContract))

(export gerbil-ascent-relation
        gerbil-ascent-lattice
        gerbil-ascent-variable
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
        gerbil-ascent-rule
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
(def Program. (.ref GerbilAscentProgramContract 'proto))

;;; Clause lowering has one open receiver axis. The evaluator consumes the
;;; resulting private plan without dispatching through POO in the row loop.
(.defgeneric (gerbil-ascent-clause-plan clause atom-plan bound)
  slot: .plan)

(def (require-bound names bound)
  (for-each
   (lambda (name)
     (unless (memq name bound)
       (error "unbound ASCENT clause variable" name)))
   names))

(def (pattern-outputs term)
  (and (eq? (car term) 'pattern)
       (vector-ref (cdr term) 0)))

(def (indexed-atom plan bound)
  (let loop ((terms (vector-ref plan 1)) (column 0)
             (columns []) (seen-bound bound))
    (if (null? terms)
      (vector (vector-ref plan 0) (vector-ref plan 1)
              (reverse columns))
      (let* ((term (car terms))
             (kind (car term))
             (inputs (and (eq? kind 'expression)
                          (vector-ref (cdr term) 0))))
        (when inputs (require-bound inputs seen-bound))
        (loop (cdr terms) (+ column 1)
              (if (or (eq? kind 'literal)
                      (and (eq? kind 'variable)
                           (memq (cdr term) bound))
                      (and inputs
                           (andmap (lambda (name) (memq name bound)) inputs)))
                (cons column columns)
                columns)
              (cond
               ((eq? kind 'variable) (cons (cdr term) seen-bound))
               ((eq? kind 'pattern)
                (append (pattern-outputs term) seen-bound))
               (else seen-bound)))))))

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
  (let (plan (indexed-atom (atom-plan clause) bound))
    (for-each
     (lambda (term)
       (when (eq? (car term) 'pattern)
         (error "ASCENT pattern cannot bind in negation"))
       (when (and (eq? (car term) 'variable)
                  (not (memq (cdr term) bound)))
         (error "unsafe ASCENT negation variable" (cdr term))))
     (vector-ref plan 1))
    (vector (vector 'negation plan) bound 0)))

(def (computed-clause-plan clause kind function-slot bound)
  (let* ((inputs (.ref clause 'variables))
         (name (.ref clause 'variable))
         (names (if (and (eq? kind 'generator) (list? name))
                  name (list name))))
    (require-bound inputs bound)
    (let loop ((remaining names) (next-bound bound))
      (if (null? remaining)
        (vector
         (vector kind
                 (if (list? name)
                   (map (lambda (output)
                          (cons 'variable output))
                        name)
                   name)
                 inputs (.ref clause function-slot))
         next-bound 0)
        (begin
          (when (memq (car remaining) next-bound)
            (error "ASCENT computed variable already bound"
                   (car remaining)))
          (loop (cdr remaining)
                (cons (car remaining) next-bound)))))))

(def (aggregate-clause-plan clause atom-plan bound)
  (let* ((plan (indexed-atom (atom-plan clause) bound))
         (name (.ref clause 'variable))
         (names (if (list? name) name (list name)))
         (inputs (.ref clause 'variables))
         (terms (vector-ref plan 1)))
    (when (ormap pattern-outputs terms)
      (error "ASCENT pattern cannot bind in aggregate"))
    (let loop ((remaining names) (next-bound bound))
      (unless (null? remaining)
        (when (memq (car remaining) next-bound)
          (error "ASCENT aggregate variable already bound"
                 (car remaining)))
        (loop (cdr remaining) (cons (car remaining) next-bound))))
    (for-each
     (lambda (input)
       (unless (ormap (lambda (term)
                        (and (eq? (car term) 'variable)
                             (eq? (cdr term) input)))
                      terms)
         (error "ASCENT aggregate input absent from atom" input)))
     inputs)
    (vector (vector 'aggregate plan name inputs (.ref clause 'aggregate)
                    (.ref clause 'output-pattern))
            (append names bound) 0)))

(def (gerbil-ascent-relation relation-name column-count source-rows
                             (provider-value gerbil-ascent-hash-index-provider)
                             (storage-value gerbil-ascent-set-storage-provider))
  (unless (and (symbol? relation-name)
               (exact-integer? column-count) (<= 0 column-count)
               (list? source-rows))
    (error "invalid ASCENT relation declaration" relation-name column-count))
  (for-each
   (lambda (row)
     (unless (and (list? row) (= (length row) column-count))
       (error "invalid ASCENT relation row" relation-name row column-count)))
   source-rows)
  (validate GerbilAscentRelationContract
            (.o (:: @ Relation.)
                name: relation-name arity: column-count rows: source-rows
                storage-kind: 'relation index-provider: provider-value
                storage-provider: storage-value)))

(def (gerbil-ascent-lattice relation-name column-count source-rows
                            join-procedure
                            (provider-value gerbil-ascent-hash-index-provider))
  (unless (and (symbol? relation-name)
               (exact-integer? column-count) (> column-count 0)
               (list? source-rows) (procedure? join-procedure))
    (error "invalid ASCENT lattice declaration" relation-name column-count))
  (for-each
   (lambda (row)
     (unless (and (list? row) (= (length row) column-count))
       (error "invalid ASCENT lattice row" relation-name row column-count)))
   source-rows)
  (validate GerbilAscentLatticeContract
            (.o (:: @ Lattice.)
                name: relation-name arity: column-count rows: source-rows
                storage-kind: 'lattice join: join-procedure
                index-provider: provider-value)))

(def (gerbil-ascent-variable name)
  (unless (symbol? name) (error "ASCENT variable name must be a symbol" name))
  (validate GerbilAscentTermContract
            (.o (:: @ Term.) kind: 'variable value: name)))

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

(def (gerbil-ascent-guard input-variables guard-procedure)
  (validate GerbilAscentGuardContract
            (.o (:: self Guard.) ascent-clause-kind: 'guard
                variables: input-variables
                predicate: guard-procedure
                (.plan (lambda (_atom-plan bound)
                         (require-bound (.ref self 'variables) bound)
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
                            binding-procedure)
  (validate GerbilAscentBindingContract
            (.o (:: self Binding.) ascent-clause-kind: 'binding
                variable: output-variable variables: input-variables
                compute: binding-procedure
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
                              (matcher #f))
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
                (.plan (lambda (atom-plan bound)
                         (aggregate-clause-plan self atom-plan bound))))))

(def (gerbil-ascent-rule head-atoms body-atoms)
  (validate GerbilAscentRuleContract
            (.o (:: @ Rule.) heads: head-atoms body: body-atoms)))

(def (gerbil-ascent-program declared-relations declared-rules
                                     input-fact-limit derived-fact-limit
                                     output-fact-limit)
  (validate GerbilAscentProgramContract
            (.o (:: @ Program.)
                relations: declared-relations rules: declared-rules
                max-input-facts: input-fact-limit
                max-derived-facts: derived-fact-limit
                max-output-facts: output-fact-limit)))
