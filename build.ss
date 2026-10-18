#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in "build-modules.ss" gerbil-ascent-library-modules)
        (only-in :std/build-script defbuild-script)
        (only-in :std/make make-clean)
        (only-in :gerbil/compiler execute-pending-compile-jobs!)
        (only-in :std/source this-source-file)
        (only-in :gerbil/runtime/loader add-load-path!)
        (only-in "bindings/artifact.ss"
                 observe-compiler-outputs reuse-compiler-outputs!
                 source-snapshot artifact-receipt! artifact-invalidated-modules clean-compiled-resources!)
        (only-in :asp-gerbil-scheme/building-api
                 asp-gerbil-scheme-package-spec!
                 asp-gerbil-scheme-library-package-prototype))


(asp-gerbil-scheme-package-spec!
 (gerbil-ascent-library-package-spec
  @ asp-gerbil-scheme-library-package-prototype)
 (spec gerbil-ascent-build-spec)
 (modules gerbil-ascent-library-modules)
 (extra-spec
  (let* ((c-dir (path-expand "bindings/c" (path-directory (this-source-file))))
         (c-options (string-append "-fPIC -I" c-dir))
         (module-link-options (cond-expand
           (darwin "-Wl,-undefined,dynamic_lookup")
           (else "")))
         (library-link-options (string-append
           (cond-expand
             (darwin "-dynamiclib -Wl,-install_name,@rpath/libascent.dylib -Wl,-undefined,dynamic_lookup -Wl,-no_compact_unwind")
             (else "-shared"))
           " " (getenv "LDFLAGS" ""))))
    `((gxc: "interface/c-api" "-ld-options" ,module-link-options)
      (gxc: "interface/runtime"
            (extra-inputs: (,(path-expand "runtime.c" c-dir)
                            ,(path-expand "ascent.h" c-dir)))
            "-cc-options" ,c-options "-ld-options" ,module-link-options)
      (exe: "interface/entry" bin: "libascent"
            "-cc-options" ,c-options "-ld-options" ,library-link-options)
      (exe: "interface/develop" bin: "ascent-develop")))))
(export gerbil-ascent-library-modules main)
(def (build-library spec . args)
  (def (run spec)
    (defbuild-script spec
      optimize: (not (equal? (getenv "GERBIL_BUILD_OPTIMIZE" "1") "0")))
    (apply main args))
  (def (executable? target)
    (and (pair? target) (eq? (car target) exe:)))
  (if (or (null? args) (equal? (car args) "compile"))
    (let ((libraries (filter (lambda (target) (not (executable? target))) spec))
          (executables (filter executable? spec)))
      ;; Including the first executable lets std/make reuse each module's
      ;; generated C/object for both its dynamic bundle and the static link.
      ;; One executable per call still prevents competing gsc -link writers.
      (let (observe (observe-compiler-outputs))
        (run (append libraries (if (pair? executables) [(car executables)] [])))
        ;; make drains parallel jobs; close the observer's idle executor too
        ;; when a synchronous or unchanged-input build submitted no jobs.
        (execute-pending-compile-jobs!)
        (let (outputs (observe (path-expand "lib/gerbil-ascent" (gerbil-path))))
          (for-each (lambda (target)
                      (reuse-compiler-outputs! outputs)
                      (displayln "... link target " (cadr target)
                                 " admitted-outputs=" (length outputs))
                      (run [target]))
                    (if (pair? executables) (cdr executables) [])))))
    (run spec)))

(def (main . args)
  (let* ((build? (or (null? args) (equal? (car args) "compile")))
         (root (path-directory (this-source-file)))
         (modules (append gerbil-ascent-library-modules
                          '("interface/c-api" "interface/runtime" "interface/entry" "interface/develop")))
         (before (and build? (source-snapshot root modules)))
         (spec (gerbil-ascent-build-spec)))
    (add-load-path! (path-expand "lib" (gerbil-path)))
    (when build?
      (let (invalidated (artifact-invalidated-modules root modules before))
        (if invalidated
          (unless (null? invalidated)
            (clean-compiled-resources! (path-expand "lib/gerbil-ascent" (gerbil-path)) invalidated)
            (make-clean
              (filter (lambda (spec)
                        (member (if (string? spec) spec (cadr spec)) invalidated))
                      spec) srcdir: root))
          (begin
            (clean-compiled-resources! (path-expand "lib/gerbil-ascent" (gerbil-path)) modules)
            (build-library spec "clean")))))
    (apply build-library spec args)
    (when build? (artifact-receipt! root modules before))))
