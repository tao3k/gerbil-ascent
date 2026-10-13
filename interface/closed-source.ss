;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Conservative native lowering of closed core forms. Unknown syntax is
;;; selected before construction and stays with the upstream macro pipeline.
(import (only-in :std/list/list delete-duplicates/hash)
        (only-in :gerbil-ascent/program/objects
  gerbil-ascent-relation gerbil-ascent-variable gerbil-ascent-wildcard
  gerbil-ascent-literal gerbil-ascent-atom gerbil-ascent-negation
  gerbil-ascent-guard gerbil-ascent-rule gerbil-ascent-fragment gerbil-ascent-program)
  (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
  (only-in :gerbil-ascent/table/storage gerbil-ascent-set-storage-provider))
(export ascent-closed-dsl-parts ascent-closed-dsl-forms? ascent-closed-dsl-core-name?)

(def operators
  (list (cons '< <) (cons '<= <=) (cons '> >) (cons '>= >=) (cons '= =) (cons 'equal? equal?)
        (cons '+ +) (cons '- -) (cons '* *) (cons 'not not)
        (cons 'even? even?) (cons 'odd? odd?) (cons 'zero? zero?)
        (cons 'positive? positive?) (cons 'negative? negative?)))
(def syntax-names '(and or if quote))
(def (literal? value)
  (or (number? value) (string? value) (boolean? value)
      (match value (['quote datum] (or (symbol? datum) (number? datum)
                                     (string? datum) (boolean? datum))) (_ #f))))
(def (literal value) (match value (['quote datum] datum) (_ value)))
(def (term? value)
  (or (symbol? value) (literal? value)
      (match value (['lit datum] (literal? datum)) (_ #f))))
(def (atom? value)
  (and (list? value) (pair? value) (symbol? (car value)) (andmap term? (cdr value))))
(def (heads? value)
  (or (atom? value) (and (list? value) (pair? value) (andmap atom? value))))
(def (operator-arity? operator operands)
  (if (memq operator '(not even? odd? zero? positive? negative?))
    (= (length operands) 1) (= (length operands) 2)))
(def (expression? value inputs)
  (cond ((symbol? value) (and (memq value inputs) #t))
        ((literal? value) #t)
        (else
         (match value
           ([operator . operands]
            (and (list? operands)
                 (or (memq operator '(and or))
                     (and (assq operator operators) (operator-arity? operator operands)))
                 (andmap (cut expression? <> inputs) operands)))
           (_ #f)))))
(def (guard? inputs expression)
  (and (list? inputs) (<= (length inputs) +closed-guard-arity+) (andmap symbol? inputs)
       (= (length inputs) (length (delete-duplicates/hash inputs)))
       (not (ormap (lambda (name) (or (assq name operators) (memq name syntax-names))) inputs))
       (expression? expression inputs)))
(def (clause? clause)
  (match clause
    (['not atom] (atom? atom))
    (['if inputs expression] (guard? inputs expression))
    (_ (and (atom? clause)
            (not (memq (car clause) '(not if guard bind let for if-let match aggregate)))))))
(def (column? column)
  (match column
    ([name predicate] (and (symbol? name)
      (memq predicate '(symbol? integer? exact-integer? boolean? string?))))
    (_ #f)))
(def (declaration? declaration)
  (match declaration
    (['relation name columns]
     (and (symbol? name) (list? columns) (andmap column? columns)))
    ([head '<-- . body]
     (and (heads? head) (list? body) (pair? body) (andmap clause? body)))
    (_ #f)))
(def (part? form)
  (and (list? form) (pair? form) (memq (car form) '(ascent ascent-fragment))
       (andmap declaration? (cdr form))))

(def (compile-expression value bindings)
  (cond ((symbol? value)
         (let (index (cdr (assq value bindings))) (lambda (arguments) (list-ref arguments index))))
        ((literal? value) (let (datum (literal value)) (lambda (_) datum)))
        (else
         (let* ((operator (car value))
                (children (map (cut compile-expression <> bindings) (cdr value))))
           (case operator
             ((and)
              (lambda (arguments)
                (let loop ((rest children) (value #t))
                  (if (null? rest) value
                    (let (next ((car rest) arguments))
                      (and next (loop (cdr rest) next)))))))
             ((or)
              (lambda (arguments)
                (let loop ((rest children))
                  (and (pair? rest) (or ((car rest) arguments) (loop (cdr rest)))))))
             (else
              (let (procedure (cdr (assq operator operators)))
                (lambda (arguments)
                  (apply procedure (map (lambda (child) (child arguments)) children))))))))))
(def (lower-term value)
  (cond ((eq? value '_) (gerbil-ascent-wildcard))
        ((symbol? value) (gerbil-ascent-variable value))
        (else (gerbil-ascent-literal
               (literal (match value (['lit datum] datum) (_ value)))))))
(def (lower-atom atom)
  (gerbil-ascent-atom (car atom) (map lower-term (cdr atom))))

;; Generate actual fixed calling shapes at build time. Unknown wider shapes
;; retain the macro route; the public language has no new arity restriction.
(defsyntax (def-guard-factory stx)
  (syntax-case stx ()
    ((_ bound-name name maximum)
     (let* ((maximum (syntax->datum #'maximum))
            (cases
       (map (lambda (n)
         (let (args (map (lambda (i) (string->symbol (string-append "argument" (number->string i)))) (iota n)))
           `((,n) (lambda ,args (evaluate (list ,@args)))))) (iota (+ maximum 1)))))
       (datum->syntax #'name
         `(begin
            (def ,(syntax->datum #'bound-name) ,maximum)
            (def (,(syntax->datum #'name) evaluate count)
              (case count ,@cases (else (error "unrecognized closed guard arity" count))))))))))
(def-guard-factory +closed-guard-arity+ make-guard-procedure 32)
(def (lower-clause clause)
  (match clause
    (['not atom] (gerbil-ascent-negation (car atom) (map lower-term (cdr atom))))
    (['if inputs expression]
     (let (evaluate (compile-expression expression (map cons inputs (iota (length inputs)))))
       (gerbil-ascent-guard inputs (make-guard-procedure evaluate (length inputs)))))
    (_ (lower-atom clause))))
(def (predicate name)
  (case name
    ((symbol?) symbol?) ((integer?) integer?) ((exact-integer?) exact-integer?)
    ((boolean?) boolean?) ((string?) string?)))
(def (lower-relation declaration)
  (let (columns (caddr declaration))
    (gerbil-ascent-relation (cadr declaration) (length columns) []
      gerbil-ascent-hash-index-provider gerbil-ascent-set-storage-provider
      (map (lambda (column) (predicate (cadr column))) columns))))
(def (lower-rule declaration)
  (let (head (car declaration))
    (gerbil-ascent-rule (map lower-atom (if (atom? head) [head] head))
                       (map lower-clause (cddr declaration)))))
(def (lower-part form)
  ;; Match the macro's final constructor order: all relations, then all rules.
  (let* ((relations (map lower-relation (filter (lambda (d) (eq? (car d) 'relation)) (cdr form))))
         (rules (map lower-rule (filter (lambda (d) (not (eq? (car d) 'relation))) (cdr form)))))
    (if (eq? (car form) 'ascent)
      (gerbil-ascent-program relations rules)
      (gerbil-ascent-fragment relations rules))))
(def (ascent-closed-dsl-core-name? name)
  (or (assq name operators) (memq name syntax-names)
      (memq name '(symbol? integer? exact-integer? boolean? string?
                   ascent ascent-fragment relation lattice macro fact facts include
                   bounds index storage define-evidence sources outputs explain lit))))
(def (ascent-closed-dsl-forms? forms) (andmap part? forms))
(def (ascent-closed-dsl-parts forms)
  ;; Never catch execution errors and retry the macro route after partial work.
  (and (ascent-closed-dsl-forms? forms) (map lower-part forms)))
