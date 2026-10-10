;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import "objects.ss" "scheme-checked.ss" "scheme-admission.ss"
        (only-in :clan/poo/object .ref))

(export relational-program relational-fragment
        relational-lattice-fragment relational-finite-view
        relational-export relational-compose relational-admit
        relational-admit/report
        relational-admission-report? relational-admission-report-admission
        relational-admission-report-diagnostic
        relational-diagnostic? relational-diagnostic-code
        relational-diagnostic-path relational-diagnostic-detail
        relational-solve relational-prepare-query relational-prepare-queries
        relational-query relational-query-name
        relational-open-session relational-session-append-source!
        relational-session-replace-source!
        relational-session-replace-sources!
        relational-session-prepare-transaction relational-session-prepare-replacements
        relational-session-transaction!
        relational-session-run relational-open-program-session
        relational-program-append-source!
        relational-program-replace-source!
        relational-program-transaction!
        relational-program-session-run relational-program-query)

;;; A rule term is syntax, not a call to an arbitrary Scheme expression.
;;; Explicit (value ...) captures one checked scalar at construction time;
;;; ?variables remain in the rule plan, so later lexical mutation cannot
;;; silently change a dependency during fixed-point evaluation.
(defsyntax (relational-term stx)
  (syntax-case stx (value)
    ((_ (value expression))
     (syntax (relational-captured-value expression)))
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

;;; Fragment atoms resolve a lexical handle after the builder allocates fresh
;;; private relation names. Reusing the same builder therefore cannot alias
;;; two fragment instances merely because their source spelling is the same.
(defsyntax (relational-atom/lexical stx)
  (syntax-case stx ()
    ((_ (name term ...))
     (identifier? (syntax name))
     (syntax (gerbil-ascent-atom name
                               (list (relational-term term) ...))))
    ((_ bad)
     (raise-syntax-error #f "expected a relational atom" (syntax bad)))))

;;; Negation lowers to an inspectable relation reference. The planner checks
;;; binding order and stratification across the whole assembled program.
(defsyntax (relational-negation stx)
  (syntax-case stx ()
    ((_ (name term ...))
     (identifier? (syntax name))
     (syntax (gerbil-ascent-negation
              'name (list (relational-term term) ...))))
    ((_ bad)
     (raise-syntax-error #f "expected a relational negation atom"
                         (syntax bad)))))

;;; The lexical variant preserves the imported handle rather than quoting a
;;; spelling; dependency analysis still sees the same negative clause kind.
(defsyntax (relational-negation/lexical stx)
  (syntax-case stx ()
    ((_ (name term ...))
     (identifier? (syntax name))
     (syntax (gerbil-ascent-negation
              name (list (relational-term term) ...))))
    ((_ bad)
     (raise-syntax-error #f "expected a relational negation atom"
                         (syntax bad)))))

;;; Reducer names are literal syntax. The runtime constructor maps only the
;;; closed numeric/count set to procedures and admission rebuilds that map.
(defsyntax (relational-reduce stx)
  (syntax-case stx ()
    ((_ output mode (input ...) (name term ...))
     (and (identifier? (syntax name))
          (identifier? (syntax mode)))
     (syntax (relational-reducer
              'output 'mode '(input ...) 'name
              (list (relational-term term) ...))))
    ((_ bad ...)
     (raise-syntax-error #f "expected checked reduction" stx))))

;;; Reduction inside a fragment binds its input to the fresh or imported
;;; relation handle, while the checked reducer descriptor stays identical.
(defsyntax (relational-reduce/lexical stx)
  (syntax-case stx ()
    ((_ output mode (input ...) (name term ...))
     (and (identifier? (syntax name))
          (identifier? (syntax mode)))
     (syntax (relational-reducer
              'output 'mode '(input ...) name
              (list (relational-term term) ...))))
    ((_ bad ...)
     (raise-syntax-error #f "expected checked reduction" stx))))

;;; Rule-local operands admit only bound logic variables or scalar values
;;; captured once during construction. A plain Scheme identifier is never
;;; interpreted as a hidden runtime callback or a literal symbol.
(defsyntax (relational-operator-input stx)
  (syntax-case stx (value)
    ((_ (value expression))
     (syntax (relational-operator-literal expression)))
    ((_ input)
     (identifier? (syntax input))
     (let* ((datum (syntax->datum (syntax input)))
            (spelling (symbol->string datum)))
       (if (and (not (eq? datum '?_))
                (> (string-length spelling) 1)
                (char=? (string-ref spelling 0) #\?))
         (syntax (vector 'variable 'input))
         (raise-syntax-error
          #f "operator input must be a ?variable or scalar literal"
          (syntax input)))))
    ((_ input)
     (let (datum (syntax->datum (syntax input)))
       (if (or (exact-integer? datum) (boolean? datum)
               (char? datum))
         (syntax (relational-operator-literal input))
         (raise-syntax-error
          #f "operator input must be an immutable scalar literal"
          (syntax input)))))))

;;; Both public forms share one rule-body grammar. The three lowering macros
;;; choose named or lexical relation references; scalar operators use the
;;; same checked descriptor path in either form. Keeping this expansion
;;; centralized prevents a fragment-only clause from bypassing admission.
(defsyntax (relational-checked-clause stx)
  (def (logic-variable? input)
    (and (identifier? input)
         (let* ((datum (syntax->datum input))
                (spelling (symbol->string datum)))
           (and (not (eq? datum '?_))
                (> (string-length spelling) 1)
                (char=? (string-ref spelling 0) #\?)))))
  (syntax-case stx (where compute not reduce)
    ((_ atom-lowering negation-lowering reduce-lowering
        (where (operation input ...)))
     (identifier? (syntax operation))
     (syntax (relational-where
              'operation (list (relational-operator-input input) ...))))
    ((_ atom-lowering negation-lowering reduce-lowering
        (compute output (operation input ...)))
     (and (logic-variable? (syntax output))
          (identifier? (syntax operation)))
     (syntax (relational-compute
              'output 'operation
              (list (relational-operator-input input) ...))))
    ((_ atom-lowering negation-lowering reduce-lowering
        (not (name term ...)))
     (syntax (negation-lowering (name term ...))))
    ((_ atom-lowering negation-lowering reduce-lowering
        (reduce output (mode input ...) (name term ...)))
     (and (logic-variable? (syntax output))
          (identifier? (syntax mode))
          (andmap logic-variable? (syntax->list (syntax (input ...)))))
     (syntax (reduce-lowering output mode (input ...)
                              (name term ...))))
    ((_ atom-lowering negation-lowering reduce-lowering
        (name term ...))
     (and (identifier? (syntax atom-lowering))
          (identifier? (syntax name))
          (not (memq (syntax->datum (syntax name))
                     '(where compute not reduce))))
     (syntax (atom-lowering (name term ...))))
    ((_ atom-lowering negation-lowering reduce-lowering bad)
     (raise-syntax-error
      #f "expected atom, not, reduce, where, or compute clause"
                         (syntax bad)))))

;;; This collector preserves declaration and body order for the planner.
;;; The final limits form is mandatory so every compiled program has finite
;;; resource bounds before its first solve; no evaluation happens here.
(defsyntax (relational-collect stx)
  (syntax-case stx (relation lattice rule limits)
    ((_ (declared ...) (lowered ...)
        (lattice name (column ...) rows mode) rest ...)
     (and (identifier? (syntax name))
          (identifier? (syntax mode))
          (andmap identifier? (syntax->list (syntax (column ...)))))
     (syntax (relational-collect
              (declared ...
                        (relational-checked-lattice
                         'name (length '(column ...)) rows 'mode))
              (lowered ...) rest ...)))
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
                        (list (relational-checked-clause
                               relational-atom relational-negation
                               relational-reduce
                               body) ...)))
              rest ...)))
    ((_ (declared ...) (lowered ...) (limits input derived output))
     (syntax (let (relations (list declared ...))
               (gerbil-ascent-program
                relations (list lowered ...) input derived output
                (map (lambda (relation) (.ref relation 'name))
                     relations)))))
    ((_ (declared ...) (lowered ...) bad rest ...)
     (raise-syntax-error
      #f "expected relation, rule, or final limits clause"
      (syntax bad)))
    ((_ (declared ...) (lowered ...))
     (raise-syntax-error
      #f "relational-program requires a final limits clause" stx))))

;; relational-program
;;   : (-> Syntax CheckedPositiveProgramExpression)
;;   | doc m%
;;       Build a checked relational program. Source and derived values are
;;       immutable scalar atoms. Rules admit only fixed checked scalar
;;       operators, not host closures or plain Scheme identifiers. Fixed
;;       rule-local literals and explicit (value ...) inputs are captured
;;       when the program is constructed. The final
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
;;       Instantiate a checked fragment with fresh source and private
;;       predicate names. Imports are existing relation handles. Named
;;       exports are recorded on the existing typed POO fragment value.
;;
;;       # Examples
;;
;;       ```scheme
;;       (relational-fragment
;;         (import)
;;         (source (edge (from to) '((1 2))))
;;         (private (path (from to)))
;;         (export (reach path))
;;         (rule (path ?x ?y) (edge ?x ?y)))
;;       ;; => a fragment with a reach export
;;       ```
;;     %
;;; Boundary: Imports preserve caller handles while declarations get fresh names.
;;; Invariant: Separate uses of one Scheme builder cannot alias by spelling.
;;; Final graph admission checks the assembled relation namespace.
(defrules relational-fragment (import source private export rule)
  ((_ (import (import-name imported-handle) ...)
      (source (source-name (source-column ...) source-rows) ...)
      (private (private-name (private-column ...)) ...)
      (export (public-name exported-name) ...)
      (rule (head head-term ...)
            (body body-term ...) ...) ...)
   (let ((import-name imported-handle) ...
         (source-name (gensym 'source-name)) ...
         (private-name (gensym 'private-name)) ...)
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
        (list (relational-checked-clause
               relational-atom/lexical relational-negation/lexical
               relational-reduce/lexical
               (body body-term ...)) ...)) ...)
      (list (cons 'public-name exported-name) ...)
      (list source-name ...)))))
