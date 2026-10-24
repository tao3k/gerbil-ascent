;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import "declaration.ss"
        :gerbil-ascent/program/interface
        :gerbil-ascent/program/syntax
        :gerbil-ascent/program/higher-order
        :gerbil-ascent/program/scheme-checked
        :gerbil-ascent/interface/rule-module
        (only-in :clan/poo/object .ref))
(export (import: :gerbil-ascent/program/interface)
        (import: :gerbil-ascent/program/syntax)
        (import: :gerbil-ascent/program/higher-order)
        (import: :gerbil-ascent/program/scheme-checked)
        ascent-rule-module define-program
        make-declared-program recorded-rule-explanation)

;; Ordinary hygienic Scheme binding: helpers, imports, macros and native
;; Program/Fragment/operator constructors retain their upstream semantics.
(defsyntax (define-program stx)
  (def (bindings entries)
    (with-syntax (((binding ...)
                  (map (lambda (entry)
                         (syntax-case entry ()
                           (name (identifier? (syntax name))
                            (syntax (cons 'name 'name)))
                           ((name handle) (and (identifier? (syntax name))
                                               (identifier? (syntax handle)))
                            (syntax (cons 'name 'handle)))
                           ((name handle) (identifier? (syntax name))
                            (syntax (cons 'name handle)))
                           (_ (raise-syntax-error #f "Evidence binding requires a relation identifier or (label handle)" stx entry))))
                       (syntax->list entries))))
      (syntax (list binding ...))))
  (syntax-case stx (sources outputs explain)
    ((_ (constructor argument ...) (sources source ...) (outputs output ...)
        (explain explanation) clause ...)
     (with-syntax ((source-bindings (bindings (syntax (source ...))))
                   (output-bindings (bindings (syntax (output ...)))))
       (syntax (def (constructor argument ...)
                 (make-declared-program (ascent clause ...)
                   source-bindings output-bindings explanation)))))
    ((_ (constructor argument ...) (sources source ...) (outputs output ...) clause ...)
     (with-syntax ((source-bindings (bindings (syntax (source ...))))
                   (output-bindings (bindings (syntax (output ...)))))
       (syntax (def (constructor argument ...)
                 (make-declared-program (ascent clause ...)
                   source-bindings output-bindings recorded-rule-explanation)))))
    ((_ constructor (sources source ...) clause ...)
     (raise-syntax-error #f "Evidence sources must be followed by outputs" stx))
    ((_ (constructor argument ...) program explanation)
     (syntax (def (constructor argument ...) (ascent-rule-module program explanation))))
    ((_ (constructor argument ...) program)
     (syntax (def (constructor argument ...) (ascent-rule-module program))))))
