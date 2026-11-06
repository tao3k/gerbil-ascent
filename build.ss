#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (for-syntax (only-in :std/source this-source-file)
                    (only-in :yuanxu/module-system/building/source-package register-module-build-source!)))
(begin-syntax
  (register-module-build-source! (path-directory (this-source-file)) 'gerbil-ascent))
(import (only-in :gerbil/expander core-import-module)
        (only-in :clan/poo/object .o)
        (only-in :yuanxu/module-system/building/source-closure for-each-build-module)
        (only-in :yuanxu/module-system/source/static-inputs module-native-static-inputs)
        (only-in :yuanxu/module-system/building/artifacts call-with-native-static-inputs)
        (only-in :clan/poo/object .get) "init.ss"
        (only-in :std/build-script defbuild-script)
        (only-in :yuanxu/module-system/building/interface call-with-init-build-spec)
        (only-in :std/make pkg-config-libs)
        (only-in :std/source this-source-file)
        (only-in :gerbil/runtime/loader add-load-path! load-path set-load-path!))

;; BEGIN GENERATED PREPARATION COMPILER
;; Existing Gambit header policy; this limits C function size, not VM concurrency.
(def gerbil-ascent-compiler-options '("-cc-options" "-D___SINGLE_HOST_LIMIT=512"))
;; END GENERATED PREPARATION COMPILER

;; The package owns its ABI roots; Core owns borrowed compiler inputs and their
;; source guards. Traverse actual native imports, not an installed-file catalog.
(def (call-with-static-link-inputs root entries owned-identities action)
  (def contexts '())
  (def seen (make-hash-table-eq))
  (for-each
    (lambda (entry)
      (for-each-build-module (core-import-module (path-expand entry root))
        (lambda (context) (set! contexts (cons context contexts))) seen))
    entries)
  (def inputs (module-native-static-inputs (reverse contexts) owned-identities))
  (call-with-native-static-inputs (.o static-inputs: inputs) action))

(def (gerbil-ascent-library-spec)
  ((.get gerbil-ascent.init.exports std-make-spec) '("init")))

(def (gerbil-ascent-compiler-targets targets)
  (map (lambda (target)
         (append (if (string? target) (list gxc: target) target)
                 gerbil-ascent-compiler-options))
       targets))

(def (gerbil-ascent-module-link-options)
  (cond-expand (darwin "-Wl,-undefined,dynamic_lookup") (else "")))

;; The Cargo consumer supplies its already selected bridge SDK. This optional
;; native entry does not add that SDK to the logical Library's dependency graph.
(def (gerbil-ascent-rust-spec)
  (gerbil-ascent-compiler-targets
    `((gxc: "interface/hybrid" "-ld-options" ,(gerbil-ascent-module-link-options)))))

(def (gerbil-ascent-abi-spec)
  (let* ((c-dir (path-expand "bindings/c" (path-directory (this-source-file))))
         (c-options (string-append "-fPIC -I" c-dir))
         (executable-link-options (string-append
           (pkg-config-libs "openssl") " " (getenv "LDFLAGS" "")))
         (module-link-options (gerbil-ascent-module-link-options))
         (library-link-options (string-append
           (cond-expand
             (darwin "-dynamiclib -Wl,-install_name,@rpath/libascent.dylib -Wl,-undefined,dynamic_lookup -Wl,-no_compact_unwind")
             (else "-shared"))
           " " executable-link-options)))
    `((gxc: "interface/c-api" "-ld-options" ,module-link-options)
      (gxc: "interface/runtime"
            (extra-inputs: (,(path-expand "runtime.c" c-dir)
                            ,(path-expand "ascent.h" c-dir)))
            "-cc-options" ,c-options "-ld-options" ,module-link-options)
      (exe: "interface/entry" bin: "libascent"
            "-cc-options" ,c-options "-ld-options" ,library-link-options)
      (exe: "interface/develop" bin: "ascent-develop"
            "-ld-options" ,executable-link-options))))

(def (gerbil-ascent-build-spec)
  (gerbil-ascent-compiler-targets
    (append (gerbil-ascent-library-spec) (gerbil-ascent-abi-spec))))
(export gerbil-ascent-build-spec gerbil-ascent-rust-spec
        gerbil-ascent-compiler-options call-with-static-link-inputs main)
(def (build-library spec . args)
  (defbuild-script spec
    optimize: (not (equal? (getenv "GERBIL_BUILD_OPTIMIZE" "1") "0")))
  (apply main args))

(def (main . args)
  (let* ((build? (or (null? args) (equal? (car args) "compile")))
         (root (path-directory (this-source-file))))
    ;; Consume the exact init-owned library specification before adding package
    ;; compiler options and ABI link outputs. Core retains its source/product guards.
    (call-with-init-build-spec gerbil-ascent-library-spec
      (lambda (native arguments (prefix #f) (libdir #f) (bindir #f))
        (when prefix (error "unexpected foreign package build group" prefix))
        (def targets (gerbil-ascent-compiler-targets (append native (gerbil-ascent-abi-spec))))
        (def (run)
          ;; Linker output resolution is scoped to compilation. Restore it
          ;; before Core rechecks the init-owned source identities.
          (if build?
            (let (paths (load-path))
              (dynamic-wind
                (lambda () (add-load-path! (path-expand "lib" (gerbil-path))))
                (lambda () (apply build-library targets arguments))
                (lambda () (set-load-path! paths))))
            (apply build-library targets arguments)))
        (if build?
          (call-with-static-link-inputs root
            (filter-map (lambda (target)
                          (and (pair? target) (eq? (car target) exe:)
                               (string-append (cadr target) ".ss"))) targets)
            (map (lambda (target) (string->symbol (string-append "gerbil-ascent/" (cadr target)))) targets)
            run)
          (run)))
      args (path-expand "lib" (gerbil-path)))))
