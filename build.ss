#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (for-syntax (only-in :std/source this-source-file)
                    (only-in :tao3k/yuanxu/module-system/building/source-package register-module-build-source!)))
(begin-syntax
  (register-module-build-source! (path-directory (this-source-file)) 'gerbil-ascent))
(import (only-in "init.ss" gerbil-ascent.init.exports)
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
        (only-in :std/list/list filter-map find)
        (only-in :std/source this-source-file))

;; BEGIN GENERATED PREPARATION COMPILER
;; Existing Gambit header policy; this limits C function size, not VM concurrency.
(def gerbil-ascent-compiler-options '("-cc-options" "-D___SINGLE_HOST_LIMIT=512"))
;; END GENERATED PREPARATION COMPILER

(def (gerbil-ascent-compiler-target target)
  (append (if (string? target) [gxc: target] target)
          gerbil-ascent-compiler-options))

(def (gerbil-ascent-build-projection)
  (.call gerbil-ascent.init.exports .project-build '("init")))

(def (gerbil-ascent-library-modules (projection (gerbil-ascent-build-projection)))
  ;; Scheme-only preparation uses the same targets as the package build,
  ;; excluding the executables and their C ABI inputs.
  (filter-map
    (lambda (target)
      (match target
        ([exe: . _] #f)
        ([gxc: (or "interface/c-api" "interface/runtime") . _] #f)
        ((? string?) target)
        (else (cadr target))))
    (.get projection spec)))

;; Cargo supplies its bridge SDK separately from the published Library.
(def (gerbil-ascent-rust-spec)
  [(gerbil-ascent-compiler-target
     [gxc: "interface/hybrid" "-ld-options"
      (cond-expand (darwin "-Wl,-undefined,dynamic_lookup") (else ""))])])

;; Gambit writes generated C beside borrowed static Scheme. Yuanxu owns the
;; writable extent and checks the original inputs across the link.
(def (call-with-static-link-inputs source owned-identities action)
  (def contexts [])
  (for-each-build-module (core-import-module source)
    (lambda (context) (set! contexts (cons context contexts))))
  (call-with-static-compiler-inputs
    (.o static-inputs: (module-static-compiler-inputs (reverse contexts) owned-identities))
    action))

(export gerbil-ascent-build-projection gerbil-ascent-library-modules
        gerbil-ascent-rust-spec
        gerbil-ascent-compiler-options gerbil-ascent-compiler-target
        call-with-static-link-inputs main)

(def (main . args)
  (def projection (gerbil-ascent-build-projection))
  (def targets (.get projection spec))
  (def spec
    (map (lambda (target)
           (gerbil-ascent-compiler-target
             (match target
               ;; Yuanxu's Module contract admits string options. Insert
               ;; std/make's native dependency property at the call boundary.
               ([gxc: "interface/runtime" . options]
                [gxc: "interface/runtime"
                 [extra-inputs: ["bindings/c/runtime.c" "bindings/c/ascent.h"]]
                 options ...])
               (else target))))
         targets))
  (defbuild-script spec optimize: (not (equal? (getenv "GERBIL_BUILD_OPTIMIZE" "1") "0")))
  (if (or (null? args) (equal? (car args) "compile"))
    (let* ((root (path-directory (this-source-file)))
           (link (find (lambda (target) (and (pair? target) (eq? (car target) exe:))) targets))
           (source (path-expand (string-append (cadr link) ".ss") root)))
      (.call projection .prepare-compiler-contexts)
      (.call projection .with-compiler-inputs
        (lambda ()
          (call-with-build-input-path (path-expand "lib" (gerbil-path))
            (lambda ()
              (call-with-static-link-inputs source
                (.get projection compiler-identities) (cut apply main args)))
            make-source: root))))
    (apply main args)))
