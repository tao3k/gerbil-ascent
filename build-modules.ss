;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Build-time module data; importing this list does not construct PackageSpec.
(export gerbil-ascent-library-modules gerbil-ascent-build-input-modules gerbil-ascent-compiler-options)

;; BEGIN GENERATED PREPARATION COMPILER
;; Existing SDK header policy; this limits C function size, not VM concurrency.
(def gerbil-ascent-compiler-options '("-cc-options" "-D___SINGLE_HOST_LIMIT=512"))
;; END GENERATED PREPARATION COMPILER

(import (for-syntax (only-in :std/source this-source-file)
                            (only-in :yuanxu/module-system/building/source-package
                                     register-module-build-source!)))
(begin-syntax
  (register-module-build-source! (path-directory (this-source-file)) 'gerbil-ascent))
(import (only-in :clan/poo/object .get)
        (only-in :std/source this-source-file) "./init.ss")
(export gerbil-ascent-library-spec)

;; Core owns source discovery and the selected epoch. No second module inventory.
(def (gerbil-ascent-library-spec)
  ((.get gerbil-ascent.init.exports std-make-spec) '("init")))
(def (gerbil-ascent-library-modules)
  (map (lambda (target) (if (string? target) target (cadr target)))
       (gerbil-ascent-library-spec)))
;; ABI inputs are package outputs, not alternative capability declarations.
(def (gerbil-ascent-build-input-modules)
  (let* ((modules (gerbil-ascent-library-modules))
         (root (path-directory (this-source-file)))
         ;; Build roles are source-only declarations, not compiler targets.
         (builds (filter-map
                   (lambda (module)
                     (and (string-prefix? "modules/" module)
                          (equal? (path-strip-directory module) "interface")
                          (let (name (string-append (path-directory module) "build"))
                            (and (file-exists? (path-expand (string-append name ".ss") root)) name))))
                   modules)))
    (append modules builds
      '("interface/c-api" "interface/runtime" "interface/entry" "interface/develop"))))
