;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/misc/process run-process)
        :gerbil/expander
        (only-in "artifact-admission.ss" artifact-digest artifact-matching-sources?)
        (only-in "entry-cache.ss" entry-inputs entry-current? bind-entry!))
(export prepare-native-tests!)

;;; Imports and original Suite/callback bindings are frozen before execution.
;;; Each child selects exactly one registry entry; it never evaluates source.
(def (prepare-native-tests! paths cache (single? #f))
  (let* ((library (path-expand "lib" cache))
         (source (path-expand (if single? "single-test.ss" "test-pool.ss") cache))
         (binary (path-expand (if single? "single-test" "test-pool") cache))
         (imports []) (entries []))
    (add-load-path! library)
    (for-each
     (lambda (path)
       (let* ((module-path (path-expand (string-append "gerbil-ascent/" (path-strip-extension path) ".ssi") library))
              (context (import-module module-path))
              (names (filter-map
                      (lambda (exported)
                        (let (name (module-export-name exported))
                          (and (fx= (module-export-phi exported) 0)
                               (or (memq name '(test-setup! test-cleanup!))
                                   (string-suffix? "-test" (symbol->string name))) name)))
                      (module-context-export context)))
              (aliases (map (lambda (name)
                              (list name (string->symbol (string-append "entry-" (number->string (length entries)) "-" (symbol->string name))))) names))
              (suites (filter-map (lambda (pair)
                                    (and (string-suffix? "-test" (symbol->string (car pair))) (cadr pair))) aliases)))
         (when (null? suites) (error "native test module exports no Suites" path))
         (set! imports (cons `(only-in (rename-in ,(string->symbol (string-append ":gerbil-ascent/" (path-strip-extension path))) ,@aliases)
                                      ,@(map cadr aliases)) imports))
         (set! entries (cons `(cons ,path (lambda ()
                                           (TestModule ,module-path (list ,@suites) []
                                                       ,(cond ((assq 'test-setup! aliases) => cadr) (else 'void))
                                                       ,(cond ((assq 'test-cleanup! aliases) => cadr) (else 'void))))) entries))))
     paths)
    (call-with-output-file [path: source truncate: #t]
      (lambda (out)
        (display "package: gerbil-ascent/t/runner\nnamespace: gerbil-ascent/t/runner/native-registry\n" out)
        (for-each (lambda (form) (write form out) (newline out))
         `((import :std/test/base
                   (only-in :gerbil-ascent/t/performance/native-library assert-native-library!)
                   (only-in :gerbil/runtime/init __load-gxi)
                   ,@(reverse imports))
           (export main)
           (def registry (list ,@(reverse entries)))
           (def (main . args)
             (let* ((path ,(if single?
                             `(begin (unless (null? args) (error "native single test accepts no arguments" args)) ,(car paths))
                             '(match args ([path] path) (else (error "native pool requires one registry key" args)))))
                    (entry (assoc path registry)))
               (unless entry (error "unknown native test registry key" path))
               (assert-native-library!)
               ;; Macro diagnostic Cases use real Gerbil eval. AOT entries
               ;; default to the minimal evaluator; initialize the same gxi
               ;; expander environment explicitly for this registry key.
               (when (equal? path "t/qualification/ascent-syntax-test.ss")
                 (displayln "INIT-GERBIL-EXPANDER") (force-output)
                 (__load-gxi)
                 (displayln "INIT-GERBIL-EXPANDER-OK") (force-output))
               (let* ((config (TestConfig verbosity: 5 capture-output?: #f))
                      (module ((cdr entry)))
                      (harness (TestHarness path config (list module)))
                      (result (test-run! harness)))
                 (if (test-result-ok? result)
                   (begin (displayln "OK") (force-output) (exit 0))
                   (exit 42)))))))))
    ;; Reuse only this lane's last admitted entry. A different registry key,
    ;; changed source, compiled dependency, toolchain or binary is a miss.
    (let* ((generated (artifact-digest source)) (inputs (entry-inputs library))
           (receipt (string-append binary ".json")) (key (if single? (car paths) "")))
      (if (entry-current? receipt binary generated inputs key)
        (begin (displayln "NATIVE-ENTRY-CACHE-HIT") (force-output))
        (begin
          (displayln "NATIVE-ENTRY-CACHE-MISS") (force-output)
          (when (file-exists? receipt) (delete-file receipt))
          (when (file-exists? binary) (delete-file binary))
          (let (foundation (entry-inputs library #f))
            (run-process ["gxi" "-:max-heap=1G,debug=q" "t/runner/compile-entry.ss"
                          source library binary]
              stderr-redirection: #t
              coprocess: (lambda (process)
                (let loop ()
                  (let (line (read-line process))
                    (unless (eof-object? line)
                      (displayln line) (force-output) (loop))))))
            (unless (and (equal? generated (artifact-digest source))
                         (artifact-matching-sources? foundation (entry-inputs library #f)))
              (error "native test inputs changed during compilation"))
            (bind-entry! receipt binary generated (entry-inputs library) key)))))
    (setenv "ASCENT_NATIVE_TEST_ENTRY" binary)
    (if single? (setenv "ASCENT_NATIVE_TEST_REGISTRY" "") (setenv "ASCENT_NATIVE_TEST_REGISTRY" "1"))
    source))
