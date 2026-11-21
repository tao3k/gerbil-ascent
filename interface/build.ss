;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .def .o)
        (only-in :std/make append-options pkg-config-libs)
        (only-in :std/source this-source-path)
        (only-in :std/misc/process run-process)
        (only-in :std/misc/ports read-all-as-string))
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

(def (initialize-compiler-build!)
  ;; Gambit's native build profile preserves the configured compiler flags.
  ;; Set the existing function-size policy before Make starts any worker.
  (def suffix (string-append " " (cadr gerbil-ascent-compiler-options)))
  (def configured
    (or (getenv "CORCXXFLAGS_GAMBUILD" #f)
        (run-process
          (list "/bin/sh" "-c"
                "compiler_profile=$1; shift; . \"$compiler_profile\" >/dev/null; printf '%s' \"$CORCXXFLAGS_GAMBUILD\""
                "ascent-compiler-profile" (path-expand "bin/gambuild-C" (gerbil-home)))
          stdout-redirection: #t coprocess: read-all-as-string)))
  (unless (string-suffix? suffix configured)
    (setenv "CORCXXFLAGS_GAMBUILD" (string-append configured suffix))))

(.def Build
  defbuild-script: (.o spec: abi-targets)
  .prepare: (lambda (_) (initialize-compiler-build!)))
