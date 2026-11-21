;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (for-syntax
          (only-in :std/source this-source-file)
          (only-in :tao3k/yuanxu/module-system/building/source-package register-module-build-source!)))
(begin-syntax
  (register-module-build-source! (path-directory (this-source-file)) 'gerbil-ascent))

(import (only-in :std/source this-source-file)
        (only-in :clan/poo/object .get)
        (only-in :std/list/list filter-map)
        (only-in :tao3k/yuanxu/module-system/building/source-package register-module-build-source!)
        (only-in "./interface/build.ss" gerbil-ascent-compiler-options gerbil-ascent-compiler-target)
        (only-in "./init.ss" gerbil-ascent.init.exports))
(export gerbil-ascent-build-projection gerbil-ascent-library-modules
        gerbil-ascent-rust-spec gerbil-ascent-compiler-options gerbil-ascent-compiler-target)

(register-module-build-source! (path-directory (this-source-file)) 'gerbil-ascent)

(def (gerbil-ascent-build-projection)
  (.get gerbil-ascent.init.exports build))

(def (gerbil-ascent-library-modules (projection (gerbil-ascent-build-projection)))
  ;; Scheme-only preparation excludes executables and their C ABI inputs.
  (filter-map
    (lambda (target)
      (match target
        ([exe: . _] #f)
        ([gxc: (or "interface/c-api" "interface/runtime") . _] #f)
        ((? string?) target)
        (else (cadr target))))
    (.get projection std-make-spec)))

;; Cargo supplies its bridge SDK separately from the published Library.
(def (gerbil-ascent-rust-spec)
  [(gerbil-ascent-compiler-target
     [gxc: "interface/hybrid" "-ld-options"
      (cond-expand (darwin "-Wl,-undefined,dynamic_lookup") (else ""))])])
