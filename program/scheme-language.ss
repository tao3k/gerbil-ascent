;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; First executable gate for the proposed Scheme relational language.
;;; This module is intentionally separate from the old Ascent surface: it
;;; accepts only finite positive rules, with no host callbacks in recursion.
(import "objects.ss"
        (only-in "types.ss" GerbilAscentFragmentContract)
        (only-in :clan/poo/object .ref)
        (only-in :clan/poo/mop validate)
        (only-in :std/list/list append-map)
        (only-in :gerbil-ascent/table/provider
                 gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage
                 gerbil-ascent-set-storage-provider))

(export relational-program relational-fragment relational-compose)

;;; Restrict the first gate to immutable scalar atoms.  A finite source and
;;; function-free rules then have a finite active domain; the budgets below
;;; remain failure limits, never evidence of completion by truncation.
(def (relational-atom-value? value)
  (or (exact-integer? value) (boolean? value) (symbol? value) (char? value)))

(def (relational-source name arity rows)
  ;; Retain the scalar restriction on later source replacement and on
  ;; derived rows.  The relation constructor already checks every row.
  (gerbil-ascent-relation
   name arity rows
   gerbil-ascent-hash-index-provider
   gerbil-ascent-set-storage-provider
   (make-list arity relational-atom-value?)))

;;; Logic variables are visibly distinct from lexical Scheme identifiers.
;;; Plain symbols and computed terms are excluded from this first gate.
(defsyntax (relational-term stx)
  (syntax-case stx ()
    ((_ term)
     (identifier? (syntax term))
     (let* ((datum (syntax->datum (syntax term)))
            (spelling (symbol->string datum)))
       (cond
        ((eq? datum '?_)
         (syntax (gerbil-ascent-wildcard)))
        ((and (> (string-length spelling) 1)
              (char=? (string-ref spelling 0) #\?))
         (syntax (gerbil-ascent-variable 'term)))
        (else
         (raise-syntax-error
          #f "relational term must be a ?variable or scalar literal"
          (syntax term))))))
    ((_ term)
     (let (datum (syntax->datum (syntax term)))
       (if (or (exact-integer? datum) (boolean? datum)
               (char? datum))
         (syntax (gerbil-ascent-literal term))
         (raise-syntax-error
          #f "relational term must be an immutable scalar literal"
          (syntax term)))))))

;;; Boundary: A program-level atom names a relation in the assembled graph.
;;; Invariant: Its terms are lowered through the restricted scalar grammar.
(defsyntax (relational-atom stx)
  (syntax-case stx ()
    ((_ (name term ...))
     (identifier? (syntax name))
     (syntax (gerbil-ascent-atom 'name
                               (list (relational-term term) ...))))
    ((_ bad)
     (raise-syntax-error #f "expected a relational atom" (syntax bad)))))

;;; Fragment atoms use Scheme-bound relation handles.  Each source/private
;;; binding below is evaluated on each constructor call, not at macro expansion.
(defsyntax (relational-atom/lexical stx)
  (syntax-case stx ()
    ((_ (name term ...))
     (identifier? (syntax name))
     (syntax (gerbil-ascent-atom name
                               (list (relational-term term) ...))))
    ((_ bad)
     (raise-syntax-error #f "expected a relational atom" (syntax bad)))))

;;; Boundary: This collector fixes clause order and requires a final budget.
;;; Invariant: Declarations and rules remain inspectable before evaluation.
(defsyntax (relational-collect stx)
  (syntax-case stx (relation rule limits)
    ((_ (declared ...) (lowered ...)
        (relation name (column ...) rows) rest ...)
     (and (identifier? (syntax name))
          (andmap identifier? (syntax->list (syntax (column ...)))))
     (syntax (relational-collect
              (declared ...
                        (relational-source
                         'name (length '(column ...)) rows))
              (lowered ...) rest ...)))
    ((_ (declared ...) (lowered ...)
        (relation name (column ...)) rest ...)
     (and (identifier? (syntax name))
          (andmap identifier? (syntax->list (syntax (column ...)))))
     (syntax (relational-collect
              (declared ...
                        (relational-source
                         'name (length '(column ...)) []))
              (lowered ...) rest ...)))
    ((_ (declared ...) (lowered ...) (rule head body ...) rest ...)
     (syntax (relational-collect
              (declared ...)
              (lowered ...
                       (gerbil-ascent-rule
                        (list (relational-atom head))
                        (list (relational-atom body) ...)))
              rest ...)))
    ((_ (declared ...) (lowered ...) (limits input derived output))
     (syntax (gerbil-ascent-program
              (list declared ...) (list lowered ...)
              input derived output)))
    ((_ (declared ...) (lowered ...) bad rest ...)
     (raise-syntax-error
      #f "expected relation, rule, or final limits clause"
      (syntax bad)))
    ((_ (declared ...) (lowered ...))
     (raise-syntax-error
      #f "relational-program requires a final limits clause" stx))))

;; relational-program
;;   : (-> Syntax FinitePositiveProgramExpression)
;;   | doc m%
;;       Build a finite, function-free positive program.  Source values and
;;       derived values are immutable scalar atoms; syntax rejects host
;;       computation and plain Scheme identifiers inside a rule.  The final
;;       limits clause supplies resource-failure bounds.
;;
;;       # Examples
;;
;;       ```scheme
;;       (relational-program
;;         (relation edge (from to) '((1 2)))
;;         (relation path (from to))
;;         (rule (path ?x ?y) (edge ?x ?y))
;;         (limits 4 4 8))
;;       ;; => a program value; evaluating it derives path(1, 2)
;;       ```
;;     %
;;; Boundary: This frame lowers only syntax with inspectable rule dependencies.
;;; Source expressions stay lexical while rules reject host calls.
;;; Invariant: Evaluation cannot observe an undeclared changing relation.
(defsyntax (relational-program stx)
  (syntax-case stx ()
    ((_ clause ...)
     (syntax (relational-collect () () clause ...)))))

;; relational-fragment
;;   : (-> Syntax FirstClassFragmentExpression)
;;   | doc m%
;;       Instantiate a positive fragment with fresh source and private
;;       predicate names. Imports are existing relation handles. The first
;;       result is the existing typed POO fragment; subsequent results are
;;       the selected handles, using ordinary Scheme multiple values.
;;
;;       # Examples
;;
;;       ```scheme
;;       (relational-fragment
;;         (import)
;;         (source (edge (from to) '((1 2))))
;;         (private (path (from to)))
;;         (export path)
;;         (rule (path ?x ?y) (edge ?x ?y)))
;;       ;; => two values: a fragment and its path handle
;;       ```
;;     %
;;; Boundary: Imports preserve caller handles while declarations get fresh names.
;;; Invariant: Separate uses of one Scheme builder cannot alias by spelling.
;;; Final graph admission checks the assembled relation namespace.
(defrules relational-fragment (import source private export rule)
  ((_ (import (import-name imported-handle) ...)
      (source (source-name (source-column ...) source-rows) ...)
      (private (private-name (private-column ...)) ...)
      (export exported-name ...)
      (rule (head head-term ...)
            (body body-term ...) ...) ...)
   (let ((import-name imported-handle) ...
         (source-name (gensym 'source-name)) ...
         (private-name (gensym 'private-name)) ...)
     (values
      (gerbil-ascent-fragment
       (list (relational-source source-name
                                (length '(source-column ...))
                                source-rows) ...
             (relational-source private-name
                                (length '(private-column ...))
                                []) ...)
       (list
        (gerbil-ascent-rule
         (list (relational-atom/lexical (head head-term ...)))
         (list (relational-atom/lexical
                (body body-term ...)) ...)) ...))
      exported-name ...))))

;;; Composition is inert.  The existing evaluator admits the assembled
;;; schema and dependency graph when the caller opens or solves the program.
(def (relational-compose fragments input-limit derived-limit output-limit)
  (for-each
   (lambda (fragment)
     (validate GerbilAscentFragmentContract fragment))
   fragments)
  (gerbil-ascent-program
   (append-map (lambda (fragment) (.ref fragment 'relations)) fragments)
   (append-map (lambda (fragment) (.ref fragment 'rules)) fragments)
   input-limit derived-limit output-limit))
