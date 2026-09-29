;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Hygienic source forms lower to the existing POO contracts and evaluator.
(import "objects.ss"
        (only-in :clan/poo/object .ref)
        (only-in :clan/poo/mop validate)
        (only-in "types.ss" GerbilAscentFragmentContract)
        (only-in :gerbil-ascent/table/provider
                 gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage
                 gerbil-ascent-set-storage-provider))

(export ascent ascent-fragment)

(defsyntax (ascent-term stx)
  (syntax-case stx (lit expr pat)
    ((_ (lit value))
     (syntax (gerbil-ascent-literal value)))
    ((_ (expr (input ...) value))
     (syntax (gerbil-ascent-expression
              '(input ...) (lambda (input ...) value))))
    ((_ (pat (output ...) pattern))
     (syntax (gerbil-ascent-pattern
              '(output ...)
              (lambda (value)
                (match value
                  (pattern (list output ...))
                  (_ #f))))))
    ((_ value)
     (and (identifier? (syntax value))
          (eq? (syntax->datum (syntax value)) '_))
     (syntax (gerbil-ascent-wildcard)))
    ((_ value)
     (identifier? (syntax value))
     (syntax (gerbil-ascent-variable 'value)))
    ((_ value)
     (syntax (gerbil-ascent-literal value)))))

(defsyntax (ascent-atom stx)
  (syntax-case stx ()
    ((_ (name term ...))
     (syntax (gerbil-ascent-atom 'name
                               (list (ascent-term term) ...))))))

(defsyntax (ascent-field-predicate stx)
  (syntax-case stx ()
    ((_ (name predicate))
     (identifier? (syntax name))
     (syntax predicate))
    ((_ name)
     (identifier? (syntax name))
     (syntax (lambda (_value) #t)))))

(defsyntax (ascent-field-predicates stx)
  (syntax-case stx ()
    ((_ (name ...))
     (andmap identifier? (syntax->list (syntax (name ...))))
     (syntax []))
    ((_ (column ...))
     (syntax (list (ascent-field-predicate column) ...)))))

(defsyntax (ascent-clause stx)
  (syntax-case stx ()
    ((_ (kind (output ...) operation (input ...) (name term ...) pattern))
     (eq? (syntax->datum (syntax kind)) 'aggregate)
     (syntax (gerbil-ascent-aggregate
              '(output ...) 'name (list (ascent-term term) ...)
              '(input ...) operation
              (lambda (value)
                (match value
                  (pattern (list output ...))
                  (_ (error "ASCENT aggregate pattern did not match")))))))
    ((_ (kind output operation (input ...) (name term ...)))
     (eq? (syntax->datum (syntax kind)) 'aggregate)
     (syntax (gerbil-ascent-aggregate
              'output 'name (list (ascent-term term) ...)
              '(input ...) operation)))
    ((_ (kind (name term ...)))
     (eq? (syntax->datum (syntax kind)) 'not)
     (syntax (gerbil-ascent-negation
              'name (list (ascent-term term) ...))))
    ((_ (kind (input ...) predicate))
     (eq? (syntax->datum (syntax kind)) 'guard)
     (syntax (gerbil-ascent-guard '(input ...) predicate)))
    ((_ (kind (input ...) predicate))
     (eq? (syntax->datum (syntax kind)) 'if)
     (syntax (gerbil-ascent-guard
              '(input ...) (lambda (input ...) predicate))))
    ((_ (kind output (input ...) procedure))
     (eq? (syntax->datum (syntax kind)) 'bind)
     (syntax (gerbil-ascent-binding 'output '(input ...) procedure)))
    ((_ (kind (output ...) (input ...) value pattern))
     (eq? (syntax->datum (syntax kind)) 'let)
     (syntax (gerbil-ascent-generator
              '(output ...) '(input ...)
              (lambda (input ...)
                (match value
                  (pattern (list (list output ...)))
                  (_ (error "ASCENT let pattern did not match")))))))
    ((_ (kind output (input ...) value))
     (eq? (syntax->datum (syntax kind)) 'let)
     (syntax (gerbil-ascent-binding
              'output '(input ...) (lambda (input ...) value))))
    ((_ (kind (output ...) (input ...) values pattern))
     (eq? (syntax->datum (syntax kind)) 'for)
     (syntax (gerbil-ascent-generator
              '(output ...) '(input ...)
              (lambda (input ...)
                (map (lambda (value)
                       (match value
                         (pattern (list output ...))
                         (_ (error "ASCENT for pattern did not match"))))
                     values)))))
    ((_ (kind output (input ...) values))
     (eq? (syntax->datum (syntax kind)) 'for)
     (syntax (gerbil-ascent-generator
              'output '(input ...) (lambda (input ...) values))))
    ((_ (kind (output ...) (input ...) value pattern))
     (eq? (syntax->datum (syntax kind)) 'if-let)
     (syntax (gerbil-ascent-generator
              '(output ...) '(input ...)
              (lambda (input ...)
                (match value
                  (pattern (list (list output ...)))
                  (_ []))))))
    ((_ (kind (output ...) (input) pattern))
     (eq? (syntax->datum (syntax kind)) 'match)
     (syntax (gerbil-ascent-generator
              '(output ...) '(input)
              (lambda (input)
                (match input
                  (pattern (list (list output ...)))
                  (_ []))))))
    ((_ (name term ...))
     (not (memq (syntax->datum (syntax name))
                '(aggregate not guard if bind let for if-let match)))
     (syntax (ascent-atom (name term ...))))))

(defsyntax (ascent-relation stx)
  (syntax-case stx (index storage)
    ((_ (name (column ...) source (index provider) (storage storage-provider)))
     (syntax (gerbil-ascent-relation
              'name (length '(column ...)) source provider storage-provider
              (ascent-field-predicates (column ...)))))
    ((_ (name (column ...) source (index provider)))
     (syntax (gerbil-ascent-relation
              'name (length '(column ...)) source provider
              gerbil-ascent-set-storage-provider
              (ascent-field-predicates (column ...)))))
    ((_ (name (column ...) source))
     (syntax (gerbil-ascent-relation
              'name (length '(column ...)) source
              gerbil-ascent-hash-index-provider
              gerbil-ascent-set-storage-provider
              (ascent-field-predicates (column ...)))))
    ((_ (name (column ...)))
     (syntax (gerbil-ascent-relation
              'name (length '(column ...)) []
              gerbil-ascent-hash-index-provider
              gerbil-ascent-set-storage-provider
              (ascent-field-predicates (column ...)))))))

(defsyntax (ascent-lattice stx)
  (syntax-case stx (index)
    ((_ (name (column ...) source join (index provider)))
     (syntax (gerbil-ascent-lattice
              'name (length '(column ...)) source join provider
              (ascent-field-predicates (column ...)))))
    ((_ (name (column ...) source join))
     (syntax (gerbil-ascent-lattice
              'name (length '(column ...)) source join
              gerbil-ascent-hash-index-provider
              (ascent-field-predicates (column ...)))))))

(defsyntax (ascent-rule stx)
  (syntax-case stx (<--)
    ((_ (((name term ...) ...) <-- body ...))
     (syntax (gerbil-ascent-rule
              (list (ascent-atom (name term ...)) ...)
              (list (ascent-clause body) ...))))
    ((_ ((name term ...) <-- body ...))
     (syntax (gerbil-ascent-rule
              (list (ascent-atom (name term ...)))
              (list (ascent-clause body) ...))))
    ((_ ((name term ...)))
     (syntax (gerbil-ascent-rule
              (list (ascent-atom (name term ...))) [])))))

;;; Finite disjunctions become ordinary rules at expansion time.
(defsyntax (ascent-rule-family stx)
  (syntax-case stx (or and)
    ((_ head (done ...) ((or (and branch ...) ...) rest ...))
     (syntax (append
              (ascent-rule-family head (done ...) (branch ... rest ...))
              ...)))
    ((_ head (done ...) (item rest ...))
     (syntax (ascent-rule-family head (done ... item) (rest ...))))
    ((_ head (done ...) ())
     (syntax (list (ascent-rule (head <-- done ...)))))))

(defsyntax (ascent-macro-argument stx)
  (syntax-case stx ()
    ((_ kind value)
     (eq? (syntax->datum (syntax kind)) 'expr)
     (syntax (void)))
    ((_ kind value)
     (eq? (syntax->datum (syntax kind)) 'ident)
     (if (identifier? (syntax value))
       (syntax (void))
       (raise-syntax-error
        #f "ASCENT macro ident argument must be an identifier"
        (syntax value))))
    ((_ kind value)
     (raise-syntax-error
      #f "ASCENT macro parameter kind must be expr or ident"
      (syntax kind)))))

(defsyntax (ascent-collect stx)
  (syntax-case stx (program fragment relation lattice index storage
                            macro fact facts include bounds <--)
    ((_ mode (declared ...) (lowered ...)
        (macro name ((parameter kind) ...) template ...) clause ...)
     (syntax (begin
               (ascent-macro-argument kind parameter) ...
               (let-syntax
                 ((name (syntax-rules ()
                          ((_ parameter ...)
                           (begin
                             (ascent-macro-argument kind parameter) ...
                             (ascent-fragment template ...))))))
                 (ascent-collect mode (declared ...) (lowered ...)
                                 clause ...)))))
    ((_ mode (declared ...) (lowered ...)
        (macro name (parameter ...) template ...) clause ...)
     (syntax (let-syntax
               ((name (syntax-rules ()
                        ((_ parameter ...)
                         (ascent-fragment template ...)))))
               (ascent-collect mode (declared ...) (lowered ...)
                               clause ...))))
    ((_ mode (declared ...) (lowered ...)
        (lattice name (column ...) source join (index provider)) clause ...)
     (syntax (ascent-collect
              mode
              (declared ...
                        (list (ascent-lattice
                               (name (column ...) source join
                                     (index provider)))))
              (lowered ...) clause ...)))
    ((_ mode (declared ...) (lowered ...)
        (lattice name (column ...) source join) clause ...)
     (syntax (ascent-collect
              mode
              (declared ...
                        (list (ascent-lattice (name (column ...) source join))))
              (lowered ...) clause ...)))
    ((_ mode (declared ...) (lowered ...)
        (relation name (column ...) source (index provider)
                  (storage storage-provider)) clause ...)
     (syntax (ascent-collect
              mode
              (declared ...
                        (list (ascent-relation
                               (name (column ...) source
                                     (index provider)
                                     (storage storage-provider)))))
              (lowered ...) clause ...)))
    ((_ mode (declared ...) (lowered ...)
        (relation name (column ...) source (index provider)) clause ...)
     (syntax (ascent-collect
              mode
              (declared ...
                        (list (ascent-relation
                               (name (column ...) source (index provider)))))
              (lowered ...) clause ...)))
    ((_ mode (declared ...) (lowered ...)
        (relation name (column ...) source) clause ...)
     (syntax (ascent-collect
              mode
              (declared ...
                        (list (ascent-relation (name (column ...) source))))
              (lowered ...) clause ...)))
    ((_ mode (declared ...) (lowered ...)
        (relation name (column ...)) clause ...)
     (syntax (ascent-collect
              mode
              (declared ...
                        (list (ascent-relation (name (column ...)))))
              (lowered ...) clause ...)))
    ((_ mode (declared ...) (lowered ...)
        (include imported-fragment) clause ...)
     (syntax (let (fragment-value
                   (validate GerbilAscentFragmentContract
                             imported-fragment))
               (ascent-collect
                mode
                (declared ... (.ref fragment-value 'relations))
                (lowered ... (.ref fragment-value 'rules))
                clause ...))))
    ((_ mode (declared ...) (lowered ...)
        (head <-- body ...) clause ...)
     (syntax (ascent-collect
              mode
              (declared ...)
              (lowered ... (ascent-rule-family head () (body ...)))
              clause ...)))
    ((_ mode (declared ...) (lowered ...)
        (fact (name term ...)) clause ...)
     (syntax (ascent-collect
              mode
              (declared ...)
              (lowered ... (list (ascent-rule ((name term ...)))))
              clause ...)))
    ((_ mode (declared ...) (lowered ...)
        (facts (name term ...) ...) clause ...)
     (syntax (ascent-collect
              mode
              (declared ...)
              (lowered ...
                       (list (gerbil-ascent-rule
                              (list (ascent-atom (name term ...)) ...) [])))
              clause ...)))
    ((_ mode (declared ...) (lowered ...)
        (name argument ...) clause ...)
     (and (identifier? (syntax name))
          (not (memq (syntax->datum (syntax name))
                     '(relation lattice macro fact facts include bounds))))
     (syntax (ascent-collect mode (declared ...) (lowered ...)
                             (include (name argument ...)) clause ...)))
    ((_ program (declared ...) (lowered ...)
        (bounds input derived output))
     (syntax (gerbil-ascent-program
              (append declared ...) (append lowered ...)
              input derived output)))
    ((_ fragment (declared ...) (lowered ...))
     (syntax (gerbil-ascent-fragment
              (append declared ...) (append lowered ...))))))

(defsyntax (ascent-with-default-storage stx)
  (syntax-case stx (relation index storage macro)
    ((_ mode provider (collected ...)
        (macro name ((parameter kind) ...) template ...) clause ...)
     (syntax (ascent-with-default-storage
              mode provider
              (collected ...
                         (macro name ((parameter kind) ...)
                           (default-storage provider) template ...))
              clause ...)))
    ((_ mode provider (collected ...)
        (macro name (parameter ...) template ...) clause ...)
     (syntax (ascent-with-default-storage
              mode provider
              (collected ...
                         (macro name (parameter ...)
                           (default-storage provider) template ...))
              clause ...)))
    ((_ mode provider (collected ...)
        (relation name (column ...) source (index index-provider)
                  (storage storage-provider)) clause ...)
     (syntax (ascent-with-default-storage
              mode provider
              (collected ...
                         (relation name (column ...) source
                                   (index index-provider)
                                   (storage storage-provider)))
              clause ...)))
    ((_ mode provider (collected ...)
        (relation name (column ...) source (index index-provider)) clause ...)
     (syntax (ascent-with-default-storage
              mode provider
              (collected ...
                         (relation name (column ...) source
                                   (index index-provider)
                                   (storage provider)))
              clause ...)))
    ((_ mode provider (collected ...)
        (relation name (column ...) source) clause ...)
     (syntax (ascent-with-default-storage
              mode provider
              (collected ...
                         (relation name (column ...) source
                                   (index gerbil-ascent-hash-index-provider)
                                   (storage provider)))
              clause ...)))
    ((_ mode provider (collected ...)
        (relation name (column ...)) clause ...)
     (syntax (ascent-with-default-storage
              mode provider
              (collected ...
                         (relation name (column ...) []
                                   (index gerbil-ascent-hash-index-provider)
                                   (storage provider)))
              clause ...)))
    ((_ mode provider (collected ...) clause rest ...)
     (syntax (ascent-with-default-storage
              mode provider (collected ... clause) rest ...)))
    ((_ mode provider (collected ...))
     (syntax (ascent-collect mode () () collected ...)))))

(defsyntax (ascent stx)
  (syntax-case stx (default-storage)
    ((_ (default-storage provider) clause ...)
     (syntax (ascent-with-default-storage
              program provider () clause ...)))
    ((_ clause ...)
     (syntax (ascent-with-default-storage
              program gerbil-ascent-set-storage-provider () clause ...)))))

(defsyntax (ascent-fragment stx)
  (syntax-case stx (default-storage)
    ((_ (default-storage provider) clause ...)
     (syntax (ascent-with-default-storage
              fragment provider () clause ...)))
    ((_ clause ...)
     (syntax (ascent-with-default-storage
              fragment gerbil-ascent-set-storage-provider () clause ...)))))
