;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/make pkg-config-libs)
        (only-in :std/source this-source-path))

(def abi-targets
  (let* ((module-link-options
          (cond-expand (darwin "-Wl,-undefined,dynamic_lookup") (else "")))
         (executable-link-options
          (string-append (pkg-config-libs "openssl") " " (getenv "LDFLAGS" "")))
         (library-link-options
          (string-append
            (cond-expand
              (darwin "-dynamiclib -Wl,-install_name,@rpath/libascent.dylib -Wl,-undefined,dynamic_lookup -Wl,-no_compact_unwind")
              (else "-shared"))
            " " executable-link-options)))
    (def c-options (string-append "-fPIC -I" (this-source-path "../bindings/c")))
    `((gxc: "c-api" "-ld-options" ,module-link-options)
      (gxc: "runtime" "-ld-options" ,module-link-options "-cc-options" ,c-options)
      (exe: "entry" bin: "libascent" "-ld-options" ,library-link-options "-cc-options" ,c-options)
      (exe: "develop" bin: "ascent-develop" "-ld-options" ,executable-link-options))))

(.def Build
  defbuild-script: (.o spec: abi-targets))
