#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Build only. Upstream Gerbil owns test discovery and execution.
(import (only-in :gerbil/compiler compile-exe execute-pending-compile-jobs!)
        :gerbil/expander
        (only-in :std/make make)
        :std/iter
        (only-in :std/list/list delete-duplicates/hash)
        (only-in :std/list/list-builder with-list-builder)
        :std/os/flock :std/os/device
        "library-spec.ss"
        (only-in "artifact-admission.ss" artifact-main artifact-sources artifact-matching-sources? artifact-directory!)
        (only-in "../../build.ss" gerbil-ascent-library-modules)
        (only-in :asp-gerbil-scheme/src/build-api/core-capacity initialize-native-build-core-capacity!))
(def package-library (path-expand "lib" (gerbil-path)))
(def test-cache (path-expand ".cache/ascent/native-library"))
(def (with-test-lane thunk)
  (artifact-directory! test-cache)
  (let (lock (open-output-file/lock (path-expand "lane.lock" test-cache) 120))
    (try (thunk) (finally (device-close lock)))))
(def (build-elapsed started)
  (exact->inexact (/ (- (current-jiffy) started) (jiffies-per-second))))

(def (production-output-time module)
  (let (path (path-expand (string-append "gerbil-ascent/" module ".ssi") package-library))
    (and (file-exists? path)
         (time->seconds (file-info-last-modification-time (file-info path))))))

;; Previously compiled fixtures remain build inputs. A producer or SDK update
;; must let native make refresh their imports, rather than leave stale private
;; call entry points in a warm package prefix. Cases still load through GxTest.
(def (cached-support-modules)
  (with-list-builder (collect)
    (def (visit module)
      (def output (path-expand (string-append "gerbil-ascent/" module) package-library))
      (when (file-exists? output)
        (cond
          ((eq? (file-type output) 'directory)
           (for (name (list-sort string<? (directory-files output)))
             (visit (string-append module "/" name))))
          ((and (string-suffix? ".ssi" module)
                (not (string-suffix? "-test.ssi" module))
                (file-exists? (string-append (path-strip-extension module) ".ss")))
           (collect (path-strip-extension module))))))
    (for (tree '("t/qualification" "t/performance")) (visit tree))))

(def (prepare-test-library! (tests []))
  (let* ((library package-library)
         (module-file (path-expand "modules.sexp" test-cache))
         (modules
          (append gerbil-ascent-library-modules test-library-base
            (apply append
              (map cdr
                (filter (lambda (entry) (ormap (cut member <> tests) (car entry)))
                  test-library-dependencies))))))
    ;; AOT links the complete fixture/reference closure. These support modules
    ;; previously resolved from source in gxtest; source loading is not a native
    ;; carrier dependency. Native make still owns dependency order/currentness.
    (let (support
          (map (lambda (name) (string-append "t/qualification/" (path-strip-extension name)))
               (list-sort string<?
                 (filter (lambda (name)
                           (and (string-suffix? ".ss" name)
                                (not (string-suffix? "-test.ss" name))))
                         (directory-files "t/qualification")))))
      (set! modules (delete-duplicates/hash
                      (append modules support (cached-support-modules)) from-end?: #t)))
    (call-with-output-file [path: module-file truncate: #t]
      (lambda (out) (write modules out) (newline out)))
    ;; Upstream make checks production, reference and consumer currentness.
    (add-load-path! library)
    (setenv "ASCENT_TEST_LIBRARY" library)
    (setenv "ASCENT_PERFORMANCE_MODULES" module-file)
    (setenv "GERBIL_LOADPATH"
      (string-append library ":" (current-directory) ":" (getenv "GERBIL_LOADPATH" "")))
    (let* ((consumers (map path-strip-extension tests))
           (all (append modules (filter (lambda (module) (not (member module modules))) consumers)))
           (started (current-jiffy))
           (sources (artifact-sources))
           (production-before (map production-output-time gerbil-ascent-library-modules)))
      (displayln "BUILD-TEST-LIBRARY modules=" (length all)
                 " cores=" (initialize-native-build-core-capacity!))
      (force-output)
      (displayln "BUILD-TEST-LIBRARY-PHASE inventory-before wall-seconds="
                 (build-elapsed started))
      ;; Upstream make owns dependency order, compiler threads and currentness.
      ;; Only requested native consumers compile; ordinary semantic Suites are
      ;; discovered and loaded by the standard Gerbil test entry.
      (let (phase (current-jiffy))
        (make all srcdir: (current-directory) libdir: library
              build-deps: (path-expand "build-deps" test-cache))
        (displayln "BUILD-TEST-LIBRARY-PHASE make wall-seconds=" (build-elapsed phase)))
      (let (phase (current-jiffy))
        (unless (artifact-matching-sources? sources (artifact-sources))
          (error "source changed during test library compilation"))
        (displayln "BUILD-TEST-LIBRARY-PHASE inventory-after wall-seconds=" (build-elapsed phase)))
      (displayln "BUILD-TEST-LIBRARY production-rebuilt="
                 (length (filter (lambda (same?) (not same?))
                                 (map equal? production-before
                                      (map production-output-time gerbil-ascent-library-modules)))))
      (displayln "BUILD-TEST-LIBRARY-OK wall-seconds="
                 (exact->inexact (/ (- (current-jiffy) started) (jiffies-per-second))))
      (force-output))))
(def (main . args)
  (match args
    (["library"] (with-test-lane (lambda () (prepare-test-library! (append (performance-contract-files) performance-modules)))))
    (["dsl"]
     (with-test-lane
      (lambda ()
        ;; Freeze and bind under the same compilation lock: concurrent builds
        ;; cannot replace each other's source snapshot.
        (artifact-main "freeze")
        (prepare-test-library!
         '("t/qualification/scheme-closure-contract-test.ss"
           "t/qualification/scheme-artifact-test.ss"
           "t/qualification/scheme-provenance-graph-test.ss"
           "t/qualification/scheme-higher-order-test.ss"
           "t/qualification/ascent-index-lifecycle-test.ss"
           "t/qualification/scheme-finite-mapping-test.ss"
    "t/qualification/scheme-session-deletion-test.ss"
    "t/qualification/ascent-timeout-test.ss"
    "t/qualification/scheme-stratified-provenance-test.ss"
    "t/qualification/scheme-model-closure-test.ss"
           "t/qualification/scheme-operator-test.ss"
           "t/qualification/scheme-library-contract-test.ss"
           "t/qualification/scheme-operator-retained-test.ss"
           "t/qualification/ascent-finite-evidence-test.ss"
           "t/qualification/ascent-positive-nonmembership-test.ss"
           "t/qualification/ascent-byods-lattice-fixture.ss"
           "t/qualification/ascent-session-corpus.ss"
           "t/qualification/ascent-byods-session-output.ss"
           "t/qualification/ascent-multi-source-session-output.ss"
           "t/qualification/ascent-grouped-eqrel-session-output.ss"
           "t/qualification/ascent-byods-lattice-session-output.ss"
           "t/qualification/ascent-arity-repetition-output.ss"
           "t/qualification/ascent-eqrel-program-output.ss"
           "t/qualification/ascent-byods-query-output.ss"
           "t/model/source-closure.ss"
           "t/model/study.ss"))
        ;; Output-dir precedence binds the executable to this current Library,
        ;; even when GERBIL_PATH also contains an older installed ASCENT.
        (let ((source "t/model/study.ss")
              (options [output-dir: package-library
                        output-file: (path-expand "dsl-closure" test-cache)
                        parallel: #t verbose: #t invoke-gsc: #t static: #t]))
          ;; This lane owns the static cache. timeout terminates the previous
          ;; build process group, but gxc's existence-based object locks can
          ;; survive SIGTERM. Recover only this lane's object locks, never
          ;; dependency-prefix locks or the advisory lane lock.
          (let (static-dir (path-expand "static" package-library))
            (when (file-exists? static-dir)
              (for-each
               (lambda (name)
                 (when (and (string-prefix? "gerbil-ascent__" name)
                            (string-suffix? ".o.lock" name))
                   (displayln "RECOVER-OBJECT-LOCK " name)
                   (delete-file (path-expand name static-dir))))
               (directory-files static-dir))))
          ;; gxc also locks the executable stub in the cache root. These two
          ;; exact paths belong to this entry, not another compiler or prefix.
          (for-each
           (lambda (name)
             (let (path (path-expand name test-cache))
               (when (file-exists? path)
                 (displayln "RECOVER-ENTRY-OBJECT-LOCK " name)
                 (delete-file path))))
           '("dsl-closure__exe.o.lock" "dsl-closure__exe_.o.lock"))
          ;; An old executable must never survive a no-op/failed compilation.
          (let (binary (path-expand "dsl-closure" test-cache))
            (when (file-exists? binary) (delete-file binary)))
          ;; make owns module freshness; only regenerate the executable stub.
          (compile-exe source options)
          ;; Drain every queued object and the compiler's link barrier before
          ;; binding. Compiler exceptions propagate; no partial binary qualifies.
          (execute-pending-compile-jobs!)
          (artifact-main "bind")))))
    (else (error "invalid test library build mode" args)))
  ;; Compilation and artifact binding have completed and the lane is closed.
  ;; Compiler imports may initialize idle library threads; this CLI is finite.
  (exit 0))
