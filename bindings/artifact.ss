;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Record successful native build inputs and already compiled resources.
(import :gerbil/expander
        (only-in :gerbil/runtime/loader add-load-path! __find-library-module)
        :std/crypto/digest :std/encoding/hex :std/encoding/json :std/error
        (only-in :std/io call-with-file-reader))
(export source-snapshot artifact-receipt! artifact-source-current?
        artifact-invalidated-modules artifact-changed-modules
        record-compiled-resources! clean-compiled-resources! compiled-resource-error?
        artifact-file-sha256 artifact-directory-reader)

(deferror-class CompiledResourceError () compiled-resource-error?)

(def (artifact-file-sha256 path)
  ;; Use upstream compiled Reader IO even when build.ss is source loaded.
  ;; Whole-file port reads otherwise interpret byte copying in the driver.
  (call-with-file-reader path
    (lambda (reader)
      (hex-encode (digest-from-reader! (Digest::sha256) reader)))))

;; Scope this cache to one inventory. New builds observe new directory entries;
;; no filesystem currentness or successful hash is cached across builds.
(def (artifact-directory-reader (read-directory directory-files))
  (let (directories (make-hash-table))
    (lambda (directory)
      (or (hash-get directories directory)
          (let (files (read-directory directory))
            (hash-put! directories directory files)
            files)))))

;; std/make cleans declared interfaces/static outputs, not previous dynamic
;; generations or obsolete generated phases. Invalidate only this build's
;; module files, so its receipt cannot select an older compilation's resources.
(def (clean-compiled-resources! library modules)
  (def (natural? text)
    (let (number (string->number text))
      (and (exact-integer? number) (>= number 0)
           (string=? text (number->string number)))))
  (for-each (lambda (module)
    (let* ((path (path-expand module library))
           (directory (path-directory path)) (stem (path-strip-directory path)))
      (when (file-exists? directory)
        (for-each (lambda (filename)
          (let ((base (path-strip-extension filename)) (extension (path-extension filename)))
            (when (or (string=? filename (string-append stem ".ssxi.ss"))
                      (and (or (string=? extension ".scm")
                          (and (string-prefix? ".o" extension)
                               (natural? (substring extension 2 (string-length extension)))
                               (not (string=? extension ".o0"))))
                       (or (string=? base stem)
                           (and (string-prefix? (string-append stem "~") base)
                                (natural? (substring base (+ (string-length stem) 1) (string-length base)))))))
              (delete-file (path-expand filename directory))))) (directory-files directory))))) modules))

;; Resolution belongs to the upstream loader. Copy its selected generation
;; under its actual name, together with the contiguous prefix it searches.
;; Gambit linker symbols contain that filename; renaming to .o1 is invalid.
(def (record-compiled-resources! resources origins module fallback-sha)
  (let (selected (__find-library-module module))
    (unless (and selected (not (string=? (path-extension selected) ".scm")))
      (raise (CompiledResourceError "compiled module required by artifact inventory"
                                   irritants: [module selected])))
    (when selected
      (let prefix ((generation 1))
        (let* ((suffix (string-append ".o" (number->string generation)))
               (path (string-append (path-strip-extension selected) suffix))
               (relative (string-append module suffix)))
          (unless (file-exists? path)
            (error "compiled module generation changed during inventory" module generation))
          (let (sha (artifact-file-sha256 path))
            (hash-put! resources relative (hash ("path" path) ("sha256" sha)))
            (if (string=? path selected)
              (hash-put! origins relative
                (hash ("module" module) ("path" selected) ("sha256" sha)
                      ("fallbackSha256" fallback-sha)))
              (prefix (+ generation 1)))))))))

(def (source-snapshot root modules (assets []))
  (map (lambda (relative)
         (cons relative (artifact-file-sha256 (path-expand relative root))))
       (append (map (cut string-append <> ".ss") modules) assets
               '("build.ss" "bindings/c/runtime.c" "bindings/c/ascent.h"
                 "bindings/artifact.ss" "bindings/build-entry.ss"))))

;; make's timestamp cache cannot detect restoring older, different bytes.
;; A mismatched or absent build observation requires std/make's package clean
;; before rebuild; no producer substitutes its own compiler tasks.
(def (artifact-source-current? root modules)
  (with-catch false
    (lambda ()
      (let* ((library (path-expand "bin/libascent" (gerbil-path)))
             (receipt (call-with-input-file (string-append library ".json")
                        (lambda (port) (read-json port object-as-hash: #t))))
             (inputs (hash-get receipt "sourceInputs"))
             (current (source-snapshot root modules)))
        (and (equal? (hash-get receipt "librarySha256") (artifact-file-sha256 library))
             (hash-table? inputs) (= (hash-length inputs) (length current))
             (andmap (lambda (input) (equal? (hash-get inputs (car input)) (cdr input))) current))))))

;; Content admission handles restored old timestamps. std/make still owns the
;; dependency graph and all dependent rebuilds; this only invalidates changed
;; direct inputs. A changed build recipe, SDK, inventory or damaged receipt
;; requires the conservative package clean.
(def (artifact-changed-modules inputs current modules)
  (and (hash-table? inputs) (= (hash-length inputs) (length current))
       (andmap (lambda (input) (hash-key? inputs (car input))) current)
       (let ((changed (filter (lambda (input)
                              (not (equal? (hash-get inputs (car input)) (cdr input)))) current))
             (module-files (map (cut string-append <> ".ss") modules)))
         (and (andmap (lambda (input) (member (car input) module-files)) changed)
              (map (lambda (input) (path-strip-extension (car input))) changed)))))

(def (artifact-invalidated-modules root modules (current #f))
  (with-catch false
    (lambda ()
      (let* ((library (path-expand "bin/libascent" (gerbil-path)))
             (receipt (call-with-input-file (string-append library ".json")
                        (lambda (port) (read-json port object-as-hash: #t)))))
        (and (equal? (hash-get receipt "sdk") (gerbil-home))
             (equal? (hash-get receipt "sourceRoot") root)
             (equal? (hash-get receipt "librarySha256") (artifact-file-sha256 library))
             (artifact-changed-modules (hash-get receipt "sourceInputs")
                                      (or current (source-snapshot root modules)) modules))))))

(def (artifact-receipt! root modules before (assets []))
  (unless (equal? before (source-snapshot root modules assets))
    (error "native build source inputs changed; no receipt published"))
  (let* ((library (path-expand "bin/libascent" (gerbil-path)))
         (resources (make-hash-table)) (compiled-origins (make-hash-table))
         (sources (make-hash-table)) (linked (make-hash-table))
         (source-only (make-hash-table))
         (read-directory (artifact-directory-reader))
         (module-files (map (cut string-append <> ".ss") modules)))
    ;; std/make prepends the source directory while building. Resource
    ;; inventory must resolve compiled interfaces, never source fallbacks.
    (add-load-path! (path-expand "lib" (gerbil-path)))
    ;; The native expander has already resolved this metadata closure.
    ;; This is an artifact inventory, not another compilation graph.
    (import-module ':gerbil-ascent/program/syntax)
    (import-module ':gerbil-ascent/program/interface)
    (for-each (lambda (module)
                (import-module (string->symbol (string-append ":gerbil-ascent/" module))))
              (filter (lambda (module) (not (string=? module "interface/develop"))) modules))
    (for-each
     (lambda (ctx)
       (when (module-context? ctx)
         (let (id (expander-context-id ctx))
           ;; The development executable owns its local SDK syntax context;
           ;; it is not an importable component of the C ABI runtime artifact.
           (when (and (symbol? id) (not (eq? id 'gerbil-ascent/interface/develop)))
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
                                ;; Retain generated Scheme as a complete fallback.
                                (and (string=? (path-extension filename) ".scm")
                                     (or (string-prefix? (string-append stem "~") filename)
                                         (string=? filename (string-append stem ".scm")))))
                        (let ((path (path-expand filename directory))
                              (relative (string-append relative-directory filename)))
                          (hash-put! resources relative
                            (hash ("path" path) ("sha256" (artifact-file-sha256 path))))
                          (when (string=? (path-extension filename) ".scm")
                            ;; The exe: entry is linked into the Library; unlike
                            ;; gxc: modules it has no dynamic compilation target.
                            (if (member relative '("gerbil-ascent/interface/entry.scm"
                                                   "gerbil-ascent/interface/entry~0.scm"))
                              (hash-put! source-only relative "linked executable entry")
                              (record-compiled-resources! resources compiled-origins
                                (path-strip-extension relative)
                                (hash-ref (hash-ref resources relative) "sha256"))))
                        )))
                    (read-directory directory)))))))))
     (hash-values gx#__module-registry))
    (for-each (lambda (input)
      (let ((relative (car input)) (sha (cdr input)))
        (when (and (not (string=? relative "interface/develop.ss"))
                   (member relative module-files))
          (hash-put! sources relative sha)
          (hash-put! linked (string-append "gerbil-ascent/" (path-strip-extension relative))
                     (hash ("path" (path-expand relative root)) ("sha256" sha)))))) before)
    (let* ((receipt (hash ("schema" "ascent.c-abi-build.v1") ("abi" 1)
                          ("buildOwner" "build.ss/std/make") ("sdk" (gerbil-home)) ("sourceRoot" root)
                          ("entryModule" ":gerbil-ascent/interface/entry")
                          ("schemeSourceSha256" sources) ("linkedSchemeSources" linked)
                          ("sourceInputs" (list->hash-table before))
                          ("syntaxResourceFormat" "gerbil-compiler-modules")
                          ("syntaxResources" resources)
                          ("compiledResourceOrigins" compiled-origins)
                          ("sourceOnlyResources" source-only)
                          ("librarySha256" (artifact-file-sha256 library))
                          ("runtimeSourceSha256" (artifact-file-sha256 (path-expand "bindings/c/runtime.c" root)))
                          ("headerSha256" (artifact-file-sha256 (path-expand "bindings/c/ascent.h" root)))))
           (output (string-append library ".json"))
           (pending (string-append output ".pending")))
      (unless (equal? before (source-snapshot root modules assets))
        (error "native build source inputs changed during inventory"))
      (call-with-output-file pending
        (lambda (port) (display (json->string receipt) port) (newline port)))
      (rename-file pending output #t))))
