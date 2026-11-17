;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .def .o .call)
        (only-in :std/make append-options pkg-config-libs)
        (only-in :std/source this-source-path)
        (only-in :tao3k/yuanxu/module-system/building/source-package
                 call-with-build-input-path))
(export Build gerbil-ascent-compiler-options gerbil-ascent-compiler-target)

;; Existing Gambit header policy; this limits C function size, not VM concurrency.
(def gerbil-ascent-compiler-options '("-cc-options" "-D___SINGLE_HOST_LIMIT=512"))

(def (gerbil-ascent-compiler-target target)
  (append (if (string? target) [gxc: target] target)
          gerbil-ascent-compiler-options))

(def abi-targets
  (let* ((module-link-options
          (cond-expand (darwin "-Wl,-undefined,dynamic_lookup") (else "")))
         (executable-link-options
          (append-options (pkg-config-libs "openssl") (getenv "LDFLAGS" "")))
         (library-link-options
          (string-append
            (cond-expand
              (darwin "-dynamiclib -Wl,-install_name,@rpath/libascent.dylib -Wl,-undefined,dynamic_lookup -Wl,-no_compact_unwind")
              (else "-shared"))
            " " executable-link-options)))
    (def c-options (string-append "-fPIC -I" (this-source-path "../bindings/c")))
    `((gxc: "c-api" "-ld-options" ,module-link-options)
      (gxc: "runtime"
        (extra-inputs: ("bindings/c/runtime.c" "bindings/c/ascent.h"))
        "-ld-options" ,module-link-options "-cc-options" ,c-options)
      (exe: "entry" bin: "libascent" "-ld-options" ,library-link-options "-cc-options" ,c-options))))

(.def Build
  defbuild-script: (.o spec: abi-targets)
  .with-static-inputs:
  (lambda (projection compile)
    (.call projection .prepare-compiler-contexts)
    (.call projection .with-compiler-inputs
      (lambda ()
        (.call projection .with-static-inputs
          (lambda ()
            ;; Admit the compiler path before static staging restores it.
            (call-with-build-input-path (path-expand "lib" (gerbil-path)) compile
              make-source: (this-source-path ".."))))))))
