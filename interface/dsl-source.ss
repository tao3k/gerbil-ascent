;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Text entry into the existing upstream DSL lowering pipeline. This does
;;; not expose a general top-level Scheme evaluator or downstream imports.
(import :gerbil/expander
        (only-in :gerbil/runtime/init gerbil-load-expander! __scheme-source)
        :gerbil-ascent/program/syntax
        :gerbil-ascent/program/interface
        "generated-resources.ss"
        (only-in :clan/poo/object .ref)
        (only-in :gerbil/runtime/gambit current-readtable
                 readtable-eval-allowed?-set readtable-sharing-allowed?-set))
(export ascent-load-dsl-sources)

(def (read-dsl text)
  (unless (and (string? text) (<= (u8vector-length (string->utf8 text)) 65536))
    (error "DSL source byte bound"))
  (parameterize ((current-readtable
                  (readtable-sharing-allowed?-set
                   (readtable-eval-allowed?-set (current-readtable) #f) #f)))
    (call-with-input-string text
      (lambda (port)
        (let (form (read port))
          (unless (and (list? form) (pair? form)
                       (memq (car form) '(ascent ascent-fragment))
                       (eof-object? (read port)))
            (error "one pure upstream DSL form required"))
          (let ((nodes 0))
            (def (visit value depth)
              (set! nodes (+ nodes 1))
              (unless (and (<= nodes 65536) (<= depth 128))
                (error "DSL structure bound"))
              (when (pair? value)
                (visit (car value) (+ depth 1))
                (visit (cdr value) depth)))
            (visit form 0))
          form)))))

(def (predicate-kind predicate)
  (cond ((eq? predicate symbol?) "symbol")
        ((or (eq? predicate exact-integer?) (eq? predicate integer?)) "integer")
        ((eq? predicate boolean?) "boolean")
        ((eq? predicate string?) "string")
        (else "scalar")))

(def (ascent-load-dsl-sources texts)
  (unless (and (list? texts) (<= 1 (length texts) 16)
               (andmap string? texts)
               (<= (apply + (map (lambda (s) (u8vector-length (string->utf8 s))) texts)) 262144))
    (error "DSL source count/total byte bound"))
  ;; std/make's generated phase files are Gambit code, not Gerbil input.
  ;; Preserve the standard raw-Scheme loading context while the explicit
  ;; upstream expander below processes the DSL and its interface metadata.
  (gerbil-load-expander!)
  (ascent-with-generated-resources (lambda ()
    (parameterize ((current-expander-context (make-top-context)))
    ;; Only syntax bindings are imported here. Runtime contracts/evaluators
    ;; are already linked into the native engine; no compiler is launched.
    (core-expand '(import :gerbil/core :gerbil-ascent/program/syntax
                          :gerbil-ascent/program/interface))
    (let* ((forms (map read-dsl texts))
           (parts (map (lambda (form) (eval-syntax form #t)) forms))
           (relations (make-hash-table-eq)) (order [])
           (rules (apply append (map (lambda (p) (.ref p 'rules)) parts)))
           (heads (make-hash-table-eq)))
      (for-each (lambda (rule)
        (for-each (lambda (head) (hash-put! heads (.ref head 'relation) #t))
                  (.ref rule 'heads))) rules)
      (for-each (lambda (part)
        (for-each (lambda (relation)
          (let* ((n (.ref relation 'name)) (old (hash-get relations n)))
            (when (and old
                       (or (not (= (.ref old 'arity) (.ref relation 'arity)))
                           (not (equal? (.ref old 'field-predicates)
                                        (.ref relation 'field-predicates)))))
              (error "incompatible DSL relation composition" n))
            (unless old
              (hash-put! relations n relation)
              (set! order (cons n order))))) (.ref part 'relations))) parts)
      (let* ((ordered (map (lambda (n) (hash-ref relations n)) (reverse order)))
             (sources (filter (lambda (n)
                        (and (not (hash-get heads n))
                             (null? (.ref (hash-ref relations n) 'rows)))) (reverse order)))
             (descriptors
              (map (lambda (relation)
                (let* ((n (.ref relation 'name)) (predicates (.ref relation 'field-predicates))
                       (columns (if (pair? predicates)
                                  (map (lambda (p) (hash ("kind" (predicate-kind p)))) predicates)
                                  (make-list (.ref relation 'arity) (hash ("kind" "scalar"))))))
                  (hash ("name" (symbol->string n)) ("columns" columns)
                        ("source" (and (memq n sources) #t))))) ordered))
             (limits (map (lambda (key default)
                       (foldl (lambda (pair bound)
                                (if (eq? (caar pair) 'ascent)
                                  (let (limit (.ref (cdr pair) key))
                                    (if (< limit bound) limit bound)) bound))
                              default (map cons forms parts)))
                         '(max-input-facts max-derived-facts max-output-facts)
                         '(+inf.0 +inf.0 +inf.0))))
        (unless (and (<= 1 (length ordered) 128) (<= (length rules) 256))
          (error "DSL program declaration bound"))
        (values (gerbil-ascent-program ordered rules (car limits) (cadr limits) (caddr limits) sources)
                descriptors (map symbol->string (reverse order)))))))))
