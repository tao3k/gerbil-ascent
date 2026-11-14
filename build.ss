#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (for-syntax (only-in :std/source this-source-file)
                    (only-in :tao3k/yuanxu/module-system/building/source-package register-module-build-source!)))
(begin-syntax
  (register-module-build-source! (path-directory (this-source-file)) 'gerbil-ascent))
(import (only-in "init.ss" gerbil-ascent.init.exports)
        (only-in :clan/poo/object .call .get)
        (only-in :tao3k/yuanxu/module-system/building/source-package
                 call-with-build-input-path)
        (only-in :std/build-script defbuild-script)
        (only-in :std/list/list filter-map)
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

(export gerbil-ascent-build-projection gerbil-ascent-library-modules
        gerbil-ascent-rust-spec
        gerbil-ascent-compiler-options gerbil-ascent-compiler-target main)

(def (main . args)
  (def projection (gerbil-ascent-build-projection))
  (def spec (map gerbil-ascent-compiler-target (.get projection spec)))
  (defbuild-script spec optimize: (not (equal? (getenv "GERBIL_BUILD_OPTIMIZE" "1") "0")))
  (if (or (null? args) (equal? (car args) "compile"))
    (begin
      (.call projection .prepare-compiler-contexts)
      (.call projection .with-compiler-inputs
        (lambda ()
          (call-with-build-input-path (path-expand "lib" (gerbil-path))
            (lambda () (.call projection .with-static-inputs (cut apply main args)))
            make-source: (path-directory (this-source-file))))))
    (apply main args)))
