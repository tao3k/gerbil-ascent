;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; First executable gate for the proposed Scheme relational language.
;;; This module is intentionally separate from the old Ascent surface: it
;;; accepts only finite positive rules, with no host callbacks in recursion.
(import "objects.ss"
        (only-in :gerbil-ascent/table/provider
                 gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage
                 gerbil-ascent-set-storage-provider))

(export relational-program)

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

(defsyntax (relational-atom stx)
  (syntax-case stx ()
    ((_ (name term ...))
     (identifier? (syntax name))
     (syntax (gerbil-ascent-atom 'name
                               (list (relational-term term) ...))))
    ((_ bad)
     (raise-syntax-error #f "expected a relational atom" (syntax bad)))))

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
(defsyntax (relational-program stx)
  (syntax-case stx ()
    ((_ clause ...)
     (syntax (relational-collect () () clause ...)))))
