#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (for-syntax (only-in :std/source this-source-file)
                    (only-in :tao3k/yuanxu/module-system/building/source-package register-module-build-source!)))
(begin-syntax
  (register-module-build-source! (path-directory (this-source-file)) 'gerbil-ascent))
(import (only-in "init.ss" gerbil-ascent.init.exports std-make-spec)
        (only-in :clan/poo/object .call .get .o)
        (only-in :gerbil/expander core-import-module import-module current-expander-compiling?)
        (only-in :tao3k/yuanxu/module-system/building/artifacts
                 call-with-static-compiler-inputs)
        (only-in :tao3k/yuanxu/module-system/building/source-closure
                 for-each-build-module)
        (only-in :tao3k/yuanxu/module-system/building/source-package
                 call-with-build-input-path)
        (only-in :tao3k/yuanxu/module-system/source/static-inputs
                 module-static-compiler-inputs)
        (only-in :std/build-script defbuild-script)
        (only-in :std/list/list partition)
        (only-in :std/source this-source-file))

;; BEGIN GENERATED PREPARATION COMPILER
;; Existing Gambit header policy; this limits C function size, not VM concurrency.
(def gerbil-ascent-compiler-options '("-cc-options" "-D___SINGLE_HOST_LIMIT=512"))
;; END GENERATED PREPARATION COMPILER

(def (gerbil-ascent-library-spec)
  ;; Scheme-only preparation does not compile the ABI link inputs.
  (append (filter (lambda (target)
                    (match target
                      ([exe: . _] #f)
                      ([gxc: (or "interface/c-api" "interface/runtime") . _] #f)
                      (else #t)))
                  std-make-spec)
          '("init")))

;; Native Make accepts both bare module paths and option-bearing targets.
(def (gerbil-ascent-library-modules (spec (gerbil-ascent-library-spec)))
  (map (lambda (target) (if (string? target) target (cadr target)))
       spec))

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

(def (gerbil-ascent-build-spec)
  (def c-dir (path-expand "bindings/c" (path-directory (this-source-file))))
  (def c-options (list "-cc-options" (string-append "-fPIC -I" c-dir)))
  (def (with-c-inputs target)
    ;; Yuanxu v0.1.0 accepts native option strings in Module Build values.
    ;; STD Make also accepts this input plist, which tracks the C header.
    (match target
      ([gxc: "interface/runtime" . options]
       `(gxc: "interface/runtime"
              (extra-inputs: (,(path-expand "runtime.c" c-dir)
                              ,(path-expand "ascent.h" c-dir)))
              ,@c-options ,@options))
      ([exe: "interface/entry" . options]
       (append target c-options))
      (else target)))
  (gerbil-ascent-compiler-targets
    (map with-c-inputs (append std-make-spec '("init")))))

;; Gambit writes generated C beside borrowed static Scheme. Yuanxu owns the
;; writable extent and checks the original inputs across the link.
(def (call-with-static-link-inputs root entries owned-identities action)
  (def contexts [])
  (def seen (make-hash-table-eq))
  (for-each
    (lambda (entry)
      (for-each-build-module (core-import-module (path-expand entry root))
        (lambda (context) (set! contexts (cons context contexts))) seen))
    entries)
  (def inputs (module-static-compiler-inputs (reverse contexts) owned-identities))
  (call-with-static-compiler-inputs (.o static-inputs: inputs) action))

(export gerbil-ascent-library-spec gerbil-ascent-library-modules
        gerbil-ascent-build-spec gerbil-ascent-rust-spec
        gerbil-ascent-compiler-options call-with-static-link-inputs main)

(def (with-compiler-inputs spec action)
  (def root (path-directory (this-source-file)))
  (def entries
    (filter-map (lambda (target)
                  (and (eq? (car target) exe:)
                       (string-append (cadr target) ".ss")))
                spec))
  (def owned
    (map (lambda (name)
           (string->symbol (string-append "gerbil-ascent/" name)))
         (gerbil-ascent-library-modules spec)))
  (.call (.get gerbil-ascent.init.exports build) .with-compiler-inputs
    (lambda ()
      (call-with-build-input-path (path-expand "lib" (gerbil-path))
        (lambda ()
          ;; The build script has already imported the source-only declaration.
          ;; Use the compiler context for the public init product.
          (parameterize ((current-expander-compiling? #t))
            (import-module (path-expand "init.ss" root) #t))
          (call-with-static-link-inputs root entries owned action))
        make-source: root))))

(def (main . args)
  (def spec (gerbil-ascent-build-spec))
  (def optimize? (not (equal? (getenv "GERBIL_BUILD_OPTIMIZE" "1") "0")))
  (def (dispatch targets)
    (defbuild-script targets optimize: optimize?)
    (apply main args))
  ;; Gerbil handles the commands and flags. Only compilation borrows inputs.
  (if (or (null? args) (equal? (car args) "compile"))
    (with-compiler-inputs spec
      (lambda ()
        (let-values (((links modules)
                      (partition (lambda (target) (eq? (car target) exe:)) spec)))
          ;; Gambit rewrites C beside the shared static inputs. Native Make
          ;; drains each link's jobs before the next link can write there.
          (match links
            ([first . rest]
             (dispatch (append modules [first]))
             (for-each (lambda (link) (dispatch [link])) rest))
            ([] (dispatch modules))))))
    (dispatch spec)))
