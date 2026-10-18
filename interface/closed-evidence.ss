;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in "closed-source.ss" ascent-closed-dsl-forms? ascent-closed-dsl-parts
                 ascent-closed-dsl-core-name?)
        (only-in "../evidence/declaration.ss" make-declared-evidence recorded-evidence-explanation)
        (only-in :std/list/list delete-duplicates/hash))
(export ascent-closed-evidence-scope)

;; A source scope can specialize only a whole immutable declaration inventory.
;; Mutable exports, helpers, arguments, foreign imports and unknown expressions
;; remain with the original module expander before any declaration executes.
(def (binding? value)
  (or (symbol? value)
      (match value ([label handle] (and (symbol? label) (symbol? handle))) (_ #f))))
(def (bindings values)
  (map (lambda (value) (match value ([label handle] (cons label handle))
                                   (_ (cons value value)))) values))
(def (definition? form)
  (match form
    (['define-evidence [name] ['sources . sources] ['outputs . outputs] . clauses]
     (and (symbol? name) (not (ascent-closed-dsl-core-name? name))
          (list? sources) (andmap binding? sources)
          (list? outputs) (andmap binding? outputs)
          (ascent-closed-dsl-forms? `((ascent ,@clauses)))))
    (_ #f)))
(def (constructor form)
  (match form
    (['define-evidence [name] ['sources . sources] ['outputs . outputs] . clauses]
     ;; Match define-evidence: construction happens anew on each zero-arity
     ;; export invocation, not when the source scope is admitted.
     (lambda ()
       (make-declared-evidence (car (ascent-closed-dsl-parts `((ascent ,@clauses))))
         (bindings sources) (bindings outputs) recorded-evidence-explanation)))))
(def (ascent-closed-evidence-scope forms exports)
  (and (andmap definition? forms)
       (let (names (map (lambda (form) (caadr form)) forms))
         (and (= (length names) (length (delete-duplicates/hash names)))
              (or (eq? exports #t)
                  (and (list? exports) (andmap (cut memq <> names) exports)))
              (let (constructors (map (lambda (form) (cons (caadr form) (constructor form))) forms))
                (lambda (export arguments)
                  (unless (and (string? export) (< 0 (string-length export) 129) (list? arguments))
                    (error "invalid module export call"))
                  (let* ((name (string->symbol export)) (binding (assq name constructors)))
                    (unless (and binding (or (eq? exports #t) (memq name exports)))
                      (error "unknown Evidence module export" name))
                    (apply (cdr binding) arguments))))))))
