#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (for-syntax (only-in :std/source this-source-file)
                    (only-in :tao3k/yuanxu/module-system/building/source-package register-module-build-source!)))
(begin-syntax
  (register-module-build-source! (path-directory (this-source-file)) 'gerbil-ascent))
(import (only-in "init.ss" gerbil-ascent.init.exports std-make-spec)
        (only-in :clan/poo/object .call .get .o)
        (only-in :gerbil/expander core-import-module)
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

;; Yuanxu collects the Module targets. Native Make also accepts a property
;; list for the two C ABI inputs, which must invalidate runtime compilation.
(def (gerbil-ascent-build-spec spec)
  (map (lambda (target)
         (append
          (match target
            ((? string?) (list gxc: target))
            ([gxc: "interface/runtime" . options]
             [gxc: "interface/runtime"
               [extra-inputs: ["bindings/c/runtime.c" "bindings/c/ascent.h"]]
               options ...])
            (else target))
          gerbil-ascent-compiler-options))
       spec))

;; Cargo supplies its bridge SDK separately from the published Library.
(def (gerbil-ascent-rust-spec)
  (gerbil-ascent-build-spec
    [[gxc: "interface/hybrid" "-ld-options"
      (cond-expand (darwin "-Wl,-undefined,dynamic_lookup") (else ""))]]))

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

;; Both executable links write shared generated C. STD Make drains each
;; link before the next starts, using its normal module compilation capacity.
(def (build-with-links projection spec dispatch)
  (def root (path-directory (this-source-file)))
  (defvalues (links modules)
    (partition (lambda (target) (eq? (car target) exe:)) spec))
  (def entries (map (lambda (target) (string-append (cadr target) ".ss")) links))
  (def (compile-targets)
    (match links
      ([] (dispatch modules))
      ([first . rest]
       (dispatch (append modules [first]))
       (for-each (lambda (target) (dispatch [target])) rest))))
  (.call projection .prepare-compiler-contexts)
  (.call projection .with-compiler-inputs
    (lambda ()
      (call-with-build-input-path (path-expand "lib" (gerbil-path))
        (lambda ()
          (call-with-static-link-inputs root entries (.get projection compiler-identities)
            compile-targets))
        make-source: root))))

(def (main . args)
  (def projection (.call gerbil-ascent.init.exports .project-build '("init")))
  (def spec (gerbil-ascent-build-spec (.get projection spec)))
  (def optimize? (not (equal? (getenv "GERBIL_BUILD_OPTIMIZE" "1") "0")))
  (def (dispatch targets)
    (defbuild-script targets optimize: optimize?)
    (apply main args))
  (if (or (null? args) (equal? (car args) "compile"))
    (build-with-links projection spec dispatch)
    (dispatch spec)))
