;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander
        (only-in :gerbil/runtime/init gerbil-load-expander! __scheme-source)
        "native-loader.ss"
        (only-in :gerbil/runtime/gambit current-readtable
                 readtable-eval-allowed?-set readtable-sharing-allowed?-set)
        (only-in :clan/poo/object .ref))
(export ascent-load-evidence-module ascent-load-evidence-source ascent-evidence-module
        evidence-module? evidence-module-program evidence-module-explain evidence-module-bindings
        ascent-evidence-module-descriptors)

(defstruct evidence-module (program explain bindings) final: #t)
(def (ascent-evidence-module program (explain #f) (bindings []))
  (unless (or (not explain) (procedure? explain))
    (error "Evidence explanation must be a native procedure"))
  (unless (and (list? bindings) (andmap (lambda (b) (and (pair? b) (symbol? (car b)) (symbol? (cdr b)))) bindings))
    (error "Evidence bindings must pair public labels with native relation handles"))
  (make-evidence-module program explain bindings))

(def (ascent-evidence-module-descriptors program (bindings []))
  (def (kind predicate)
    (cond ((eq? predicate symbol?) "symbol")
          ((eq? predicate exact-integer?) "integer")
          ((eq? predicate boolean?) "boolean")
          ((eq? predicate string?) "string")
          (else "native")))
  (let (sources (.ref program 'source-handles))
    (unless (andmap (lambda (b) (memq (cdr b) (map (cut .ref <> 'name) (.ref program 'relations)))) bindings)
      (error "Evidence binding does not name a native relation"))
    (map (lambda (relation)
           (let* ((n (.ref relation 'name))
                  (binding (find (lambda (b) (eq? (cdr b) n)) bindings)))
             (hash ("name" (symbol->string (if binding (car binding) n)))
                   ("columns" (let (predicates (.ref relation 'field-predicates))
                     (if (pair? predicates)
                       (map (lambda (p) (hash ("kind" (kind p)))) predicates)
                       (make-list (.ref relation 'arity) (hash ("kind" "native"))))))
                   ("source" (and (memq n sources) #t)))))
         (.ref program 'relations))))

;; Modules are trusted host code, built by build.ss, not inert rule documents.
;; The constructor runs with the module's native lexical/macro environment.
(def (ascent-load-evidence-module module constructor arguments)
  (unless (and (string? module) (string-prefix? ":" module)
               (<= (string-length module) 4096)
               (string? constructor) (< 0 (string-length constructor) 129)
               (list? arguments))
    (error "invalid native Evidence module entry"))
  (gerbil-load-expander!)
  (ascent-with-generated-resources (lambda ()
    (parameterize ((current-expander-context (make-top-context)))
      (eval-syntax '(import :gerbil/core))
      (eval-syntax `(import (only-in ,(string->symbol module) ,(string->symbol constructor))))
      (let (builder (eval-syntax (string->symbol constructor) #t))
        (unless (procedure? builder) (error "Evidence constructor is not callable"))
        (apply builder arguments))))))

(def source-module-loads 0)
;; Native expansion can retain global bindings. Bound the complete runtime's
;; loads, not only live ABI owners; closing a handle does not reset this cap.
(def (ascent-load-evidence-source source trusted)
  (unless (and (eq? trusted #t) (string? source)
               (<= (u8vector-length (string->utf8 source)) 262144))
    (error "explicit trusted host Scheme authorization and Evidence DSL required"))
  (when (>= source-module-loads 64) (error "native source module runtime load limit"))
  (let* ((forms
          (parameterize ((current-readtable
                          (readtable-sharing-allowed?-set
                            (readtable-eval-allowed?-set (current-readtable) #f) #f)))
            (call-with-input-string source
              (lambda (port)
                (let loop ((forms []) (nodes 0))
                  (let (form (read port))
                    (if (eof-object? form) (reverse forms)
                      (let ()
                        (unless (and (< (length forms) 256) (list? form) (pair? form)
                                     (not (memq (car form) '(import export module))))
                          (error "Evidence definitions required; module/import/build scaffolding belongs to the Library"))
                        (def (visit value depth)
                          (set! nodes (+ nodes 1))
                          (unless (and (<= nodes 65536) (<= depth 128))
                            (error "native module source structure bound"))
                          (when (pair? value)
                            (visit (car value) (+ depth 1)) (visit (cdr value) depth)))
                        (visit form 0)
                        (loop (cons form forms) nodes)))))))))
         (context (make-top-context))
         (namespace (gensym 'ascent-source)))
    (unless (pair? forms) (error "Evidence DSL definitions required"))
    (set! source-module-loads (+ source-module-loads 1))
    (gerbil-load-expander!)
    (ascent-with-generated-resources (lambda ()
      (parameterize ((current-expander-context context))
        (eval-syntax '(import :gerbil/core))
        (eval-syntax `(module ,namespace
                       (import :gerbil-ascent/evidence/interface
                               :gerbil-ascent/evidence/module
                               (only-in :clan/poo/object .ref))
                       (export #t) ,@forms)))))
    (lambda (export arguments)
      (unless (and (string? export) (< 0 (string-length export) 129) (list? arguments))
        (error "invalid module export call"))
      (ascent-with-generated-resources (lambda ()
        (parameterize ((current-expander-context context))
          (eval-syntax `(import (only-in ,namespace ,(string->symbol export))))
          (let (procedure (eval-syntax (string->symbol export) #t))
            (unless (procedure? procedure) (error "module export is not callable"))
            (apply procedure arguments))))))))
