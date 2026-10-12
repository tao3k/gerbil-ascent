;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Record successful native build inputs and already compiled resources.
(import :gerbil/expander
        (only-in :gerbil/runtime/loader add-load-path!)
        :std/crypto/digest :std/encoding/hex :std/encoding/json)
(export native-source-snapshot native-artifact-receipt!)

(def (file-sha path)
  (hex-encode (sha256 (read-file-u8vector path))))

(def (native-source-snapshot root modules (assets []))
  (map (lambda (relative)
         (cons relative (file-sha (path-expand relative root))))
       (append (map (cut string-append <> ".ss") modules) assets
               '("build.ss" "bindings/c/runtime.c" "bindings/c/ascent.h"
                 "bindings/native-artifact.ss" "bindings/native-build-entry.ss"))))

(def (native-artifact-receipt! root modules before (assets []))
  (unless (equal? before (native-source-snapshot root modules assets))
    (error "native build source inputs changed; no receipt published"))
  (let* ((library (path-expand "bin/libascent" (gerbil-path)))
         (resources (make-hash-table))
         (sources (make-hash-table)) (linked (make-hash-table)))
    ;; std/make prepends the source directory while building. Resource
    ;; inventory must resolve compiled interfaces, never source fallbacks.
    (add-load-path! (path-expand "lib" (gerbil-path)))
    ;; The native expander has already resolved this metadata closure.
    ;; This is an artifact inventory, not another compilation graph.
    (import-module ':gerbil-ascent/program/syntax)
    (import-module ':gerbil-ascent/program/interface)
    (for-each (lambda (module)
                (import-module (string->symbol (string-append ":gerbil-ascent/" module))))
              modules)
    (for-each
     (lambda (ctx)
       (when (module-context? ctx)
         (let (id (expander-context-id ctx))
           (when (symbol? id)
             (let* ((name (symbol->string id))
                    (metadata (with-catch false
                      (lambda () (core-resolve-library-module-path
                                  (datum->syntax #f (string->symbol (string-append ":" name))))))))
               (when (and metadata (string=? (path-extension metadata) ".ssi"))
                 (let* ((directory (path-directory metadata))
                        (stem (path-strip-directory (path-strip-extension metadata)))
                        (relative-directory (path-directory name)))
                   (for-each
                    (lambda (filename)
                      (when (or (string=? filename (path-strip-directory metadata))
                                ;; The native loader already supports compiler
                                ;; generated Scheme. Avoid a separate dyld image
                                ;; for every expander phase in embedded hosts.
                                (and (string=? (path-extension filename) ".scm")
                                     (or (string-prefix? (string-append stem "~") filename)
                                         (string=? filename (string-append stem ".scm")))))
                        (let ((path (path-expand filename directory))
                              (relative (string-append relative-directory filename)))
                          (hash-put! resources relative
                            (hash ("path" path) ("sha256" (file-sha path)))))))
                    (directory-files directory)))))))))
     (hash-values gx#__module-registry))
    (for-each (lambda (input)
      (let ((relative (car input)) (sha (cdr input)))
        (when (member relative (map (cut string-append <> ".ss") modules))
          (hash-put! sources relative sha)
          (hash-put! linked (string-append "gerbil-ascent/" (path-strip-extension relative))
                     (hash ("path" (path-expand relative root)) ("sha256" sha)))))) before)
    (let* ((receipt (hash ("schema" "ascent.c-abi-build.v1") ("abi" 1)
                          ("buildOwner" "build.ss/std/make") ("sdk" (gerbil-home)) ("sourceRoot" root)
                          ("entryModule" ":gerbil-ascent/interface/native-entry")
                          ("schemeSourceSha256" sources) ("linkedSchemeSources" linked)
                          ("sourceInputs" (list->hash-table before))
                          ("syntaxResourceFormat" "gerbil-compiler-scheme")
                          ("syntaxResources" resources)
                          ("librarySha256" (file-sha library))
                          ("runtimeSourceSha256" (file-sha (path-expand "bindings/c/runtime.c" root)))
                          ("headerSha256" (file-sha (path-expand "bindings/c/ascent.h" root)))))
           (output (string-append library ".json"))
           (pending (string-append output ".pending")))
      (unless (equal? before (native-source-snapshot root modules assets))
        (error "native build source inputs changed during inventory"))
      (call-with-output-file pending
        (lambda (port) (display (json->string receipt) port) (newline port)))
      (rename-file pending output #t))))
