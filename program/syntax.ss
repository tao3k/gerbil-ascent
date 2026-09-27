;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Hygienic source forms lower to the existing POO contracts and evaluator.
(import "objects.ss")

(export ascent)

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
     (identifier? (syntax value))
     (syntax (gerbil-ascent-variable 'value)))
    ((_ value)
     (syntax (gerbil-ascent-literal value)))))

(defsyntax (ascent-atom stx)
  (syntax-case stx ()
    ((_ (name term ...))
     (syntax (gerbil-ascent-atom 'name
                               (list (ascent-term term) ...))))))

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
              'name (length '(column ...)) source provider storage-provider)))
    ((_ (name (column ...) source (index provider)))
     (syntax (gerbil-ascent-relation
              'name (length '(column ...)) source provider)))
    ((_ (name (column ...) source))
     (syntax (gerbil-ascent-relation
              'name (length '(column ...)) source)))
    ((_ (name (column ...)))
     (syntax (gerbil-ascent-relation
              'name (length '(column ...)) [])))))

(defsyntax (ascent-lattice stx)
  (syntax-case stx (index)
    ((_ (name (column ...) source join (index provider)))
     (syntax (gerbil-ascent-lattice
              'name (length '(column ...)) source join provider)))
    ((_ (name (column ...) source join))
     (syntax (gerbil-ascent-lattice
              'name (length '(column ...)) source join)))))

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

(defsyntax (ascent-collect stx)
  (syntax-case stx (relation lattice index storage fact facts bounds <--)
    ((_ (declared ...) (lowered ...)
        (lattice name (column ...) source join (index provider)) clause ...)
     (syntax (ascent-collect
              (declared ... (ascent-lattice
                             (name (column ...) source join (index provider))))
              (lowered ...) clause ...)))
    ((_ (declared ...) (lowered ...)
        (lattice name (column ...) source join) clause ...)
     (syntax (ascent-collect
              (declared ... (ascent-lattice (name (column ...) source join)))
              (lowered ...) clause ...)))
    ((_ (declared ...) (lowered ...)
        (relation name (column ...) source (index provider)
                  (storage storage-provider)) clause ...)
     (syntax (ascent-collect
              (declared ... (ascent-relation
                             (name (column ...) source
                                   (index provider) (storage storage-provider))))
              (lowered ...) clause ...)))
    ((_ (declared ...) (lowered ...)
        (relation name (column ...) source (index provider)) clause ...)
     (syntax (ascent-collect
              (declared ... (ascent-relation
                             (name (column ...) source (index provider))))
              (lowered ...) clause ...)))
    ((_ (declared ...) (lowered ...)
        (relation name (column ...) source) clause ...)
     (syntax (ascent-collect
              (declared ... (ascent-relation (name (column ...) source)))
              (lowered ...) clause ...)))
    ((_ (declared ...) (lowered ...)
        (relation name (column ...)) clause ...)
     (syntax (ascent-collect
              (declared ... (ascent-relation (name (column ...))))
              (lowered ...) clause ...)))
    ((_ (declared ...) (lowered ...)
        (head <-- body ...) clause ...)
     (syntax (ascent-collect
              (declared ...)
              (lowered ... (ascent-rule-family head () (body ...)))
              clause ...)))
    ((_ (declared ...) (lowered ...)
        (fact (name term ...)) clause ...)
     (syntax (ascent-collect
              (declared ...)
              (lowered ... (list (ascent-rule ((name term ...)))))
              clause ...)))
    ((_ (declared ...) (lowered ...)
        (facts (name term ...) ...) clause ...)
     (syntax (ascent-collect
              (declared ...)
              (lowered ...
                       (list (gerbil-ascent-rule
                              (list (ascent-atom (name term ...)) ...) [])))
              clause ...)))
    ((_ (declared ...) (lowered ...)
        (bounds input derived output))
     (syntax (gerbil-ascent-program
              (list declared ...) (append lowered ...)
              input derived output)))))

(defsyntax (ascent stx)
  (syntax-case stx ()
    ((_ clause ...)
     (syntax (ascent-collect () () clause ...)))))
