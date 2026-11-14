#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Build only. Upstream Gerbil owns test discovery and execution.
(import (only-in :gerbil/compiler compile-exe execute-pending-compile-jobs!)
        :gerbil/expander
        (only-in :std/make make)
        (only-in :asp-gerbil-scheme/src/build-api/native-spec-support normalize-spec)
        :std/iter
        (only-in :std/list/list delete-duplicates/hash)
        (only-in :std/list/list-builder with-list-builder)
        :std/os/flock :std/os/device
        "library-spec.ss"
        (only-in :std/string/path path-default-extension)
        (only-in :clan/poo/object .call .get)
        (only-in :tao3k/yuanxu/module-system/building/source-package call-with-build-input-path)
        (only-in :asp-gerbil-scheme/src/build-api/native-import-closure
                 asp-gerbil-scheme-prepared-native-import-closure
                 call-with-asp-gerbil-scheme-prepared-source-graph)
        (only-in "artifact-admission.ss" artifact-support-cache artifact-support-projection artifact-record-support-cache! artifact-main artifact-sources artifact-matching-sources? artifact-directory! artifact-compiler-options-current? artifact-record-compiler-options!)
;; BEGIN GENERATED PREPARATION IMPORT
        (only-in "../../build.ss" gerbil-ascent-compiler-options
                 gerbil-ascent-build-projection gerbil-ascent-library-modules)
;; END GENERATED PREPARATION IMPORT
        (only-in :asp-gerbil-scheme/src/build-api/core-capacity initialize-native-build-core-capacity!))
(def package-library (path-expand "lib" (gerbil-path)))
(def test-cache (path-expand ".cache/ascent/compiled-library"))
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
;; must let compiled make refresh their imports, rather than leave stale private
;; call entry points in a warm package prefix. Cases still load through GxTest.
(def (cached-support-modules (all-outputs? #f))
  (with-list-builder (collect)
    (def (visit module)
      (def output (path-expand (string-append "gerbil-ascent/" module) package-library))
      (when (file-exists? output)
        (cond
          ((eq? (file-type output) 'directory)
           (for (name (list-sort string<? (directory-files output)))
             (visit (string-append module "/" name))))
          ((and (string-suffix? ".ssi" module)
                (or all-outputs?
                    (and (not (string-suffix? "-test.ssi" module))
                         (file-exists? (string-append (path-strip-extension module) ".ss")))))
           (collect (path-strip-extension module))))))
    (for (tree (if all-outputs? '("t" "bindings" "init.ssi")
                   '("t/qualification" "t/performance")))
      (visit tree))))

;; BEGIN GENERATED PREPARATION SELECTION
;; Generated from PreparationWork.lean; formal CI compares this region.
(def (preparation-selected-dependencies tests entries)
  (apply append
    (map cdr
      (filter (lambda (entry) (ormap (cut member <> tests) (car entry))) entries))))
;; END GENERATED PREPARATION SELECTION


(def (prepare-test-library! (tests []) (source-suites? #f) (source-consumers []))
  ;; Module DSL fragments are native compiler inputs owned by init, not
  ;; standalone source modules. Keep their lowering and source-current guards
  ;; active during discovery and make, exactly as the production entry does.
  (def projection (gerbil-ascent-build-projection))
  (def production (gerbil-ascent-library-modules projection))
  (.call projection .prepare-compiler-contexts)
  (.call projection .with-compiler-inputs
    (lambda ()
      (call-with-build-input-path package-library
        (lambda () (prepare-test-library/native! production tests source-suites? source-consumers))
        make-source: (current-directory)))))

(def (prepare-test-library/native! production tests source-suites? source-consumers)
  (let* ((library package-library)
         (module-file (path-expand "modules.sexp" test-cache))
         (options-file (path-expand "gerbil-ascent/t/.compiler-options.sexp" library))
         (support-file (path-expand "support-graph.sexp" test-cache))
         (admitted-projection #f)
         (admitted-cache #f)
         (selection (list source-suites? tests source-consumers))
         (optimize? (not (equal? (getenv "GERBIL_BUILD_OPTIMIZE" "1") "0")))
         (cache-options (cons optimize? gerbil-ascent-compiler-options))
         (started (current-jiffy))
         (sources (artifact-sources))
         (inventory-seconds (build-elapsed started))
         (production-before (map production-output-time production))
         (modules
          (delete-duplicates/hash
            (append production
              (preparation-support-roots source-suites? test-library-base
                (preparation-selected-dependencies tests test-library-dependencies)
                (cached-support-modules))) from-end?: #t)))
    ;; Every source Suite remains a projection root. Gerbil supplies its actual
    ;; imports; unrelated oracle/CLI drivers are not an implicit fixture catalog.
    ;; Retain cached fixtures so make refreshes their production ABI when stale.
    ;; Source Suites remain source inputs to GxTest. Gerbil loads each root
    ;; and ASP projects the same resident contexts for std/make.
    (let* ((phase (current-jiffy))
           (roots (preparation-projection-roots production
                    modules tests source-consumers #f)))
      (let (cached (artifact-support-cache support-file sources library cache-options))
        (when cached
          (set! admitted-cache cached)
          (set! admitted-projection (artifact-support-projection cached selection modules))))
      (displayln "BUILD-TEST-LIBRARY-PHASE projection-input-admission wall-seconds="
                 (build-elapsed phase))
      (if admitted-projection
        (let (reused (current-jiffy))
          (set! modules admitted-projection)
          (displayln "BUILD-TEST-LIBRARY projection-cache-hit=1")
          (displayln "BUILD-TEST-LIBRARY-PHASE source-context-reuse wall-seconds="
                     (build-elapsed reused)))
        (let (loading (current-jiffy))
          (for-each (lambda (root) (import-module (path-default-extension root ".ss") #f #f)) roots)
          (displayln "BUILD-TEST-LIBRARY-PHASE source-context-load wall-seconds="
                     (build-elapsed loading))
          (let* ((projection-started (current-jiffy))
                 (closure
                  (call-with-asp-gerbil-scheme-prepared-source-graph
                    (lambda ()
                      (asp-gerbil-scheme-prepared-native-import-closure (current-directory) roots)))))
            (set! modules
              (delete-duplicates/hash
                (append modules
                  (map path-strip-extension
                    (filter (lambda (source)
                              (and (not (member source tests))
                                   (preparation-retained-source? source source-suites? source-consumers)))
                            closure)))
                from-end?: #t))
            (displayln "BUILD-TEST-LIBRARY-PHASE resident-context-projection wall-seconds="
                       (build-elapsed projection-started)))))
      (displayln "BUILD-TEST-LIBRARY-PHASE dependency-projection wall-seconds="
                 (build-elapsed phase)))
    (call-with-output-file [path: module-file truncate: #t]
      (lambda (out) (write modules out) (newline out)))
    ;; Upstream make checks production, reference and consumer currentness.
    (setenv "ASCENT_TEST_LIBRARY" library)
    (setenv "ASCENT_PERFORMANCE_MODULES" module-file)
    (setenv "GERBIL_LOADPATH"
      (string-append library ":" (current-directory) ":" (getenv "GERBIL_LOADPATH" "")))
    (let* ((consumers (map path-strip-extension tests))
           (all (append modules
                  (if source-suites? []
                      (filter (lambda (module) (not (member module modules))) consumers)))))
      (displayln "BUILD-TEST-LIBRARY modules=" (length all)
                 " cores=" (initialize-native-build-core-capacity!))
      (force-output)
      (displayln "BUILD-TEST-LIBRARY-PHASE inventory-before wall-seconds="
                 inventory-seconds)
      ;; Upstream make owns dependency order, compiler threads and currentness.
      ;; Only requested compiled consumers compile; ordinary semantic Suites are
      ;; discovered and loaded by the standard Gerbil test entry.
      (let (phase (current-jiffy))
        (make (map (cut normalize-spec <> gerbil-ascent-compiler-options) all)
              srcdir: (current-directory) libdir: library
              build-deps: (path-expand "build_deps" test-cache)
              optimize: optimize?)
        (displayln "BUILD-TEST-LIBRARY-PHASE make wall-seconds=" (build-elapsed phase)))
      (let (phase (current-jiffy))
        (unless (artifact-matching-sources? sources (artifact-sources))
          (error "source changed during test library compilation"))
        (displayln "BUILD-TEST-LIBRARY-PHASE inventory-after wall-seconds=" (build-elapsed phase)))
      (artifact-directory! (path-directory options-file))
      (artifact-record-compiler-options! options-file gerbil-ascent-compiler-options)
      (let (phase (current-jiffy))
        (artifact-record-support-cache! support-file sources library cache-options selection modules admitted-cache)
        (displayln "BUILD-TEST-LIBRARY-PHASE support-cache-publication wall-seconds=" (build-elapsed phase)))
      (displayln "BUILD-TEST-LIBRARY production-rebuilt="
                 (length (filter (lambda (same?) (not same?))
                                 (map equal? production-before
                                      (map production-output-time production)))))
      (displayln "BUILD-TEST-LIBRARY-OK wall-seconds="
                 (exact->inexact (/ (- (current-jiffy) started) (jiffies-per-second))))
      (force-output))))
(def (main . args)
  (match args
    (["library"] (with-test-lane (lambda ()
      (prepare-test-library! (append (performance-contract-files) performance-modules)
                             #f (performance-scenario-files)))))
    (["semantics" . tests]
     (unless (pair? tests) (error "source qualification requires its complete Suite inventory"))
     (with-test-lane (lambda () (prepare-test-library! tests #t))))
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
           "t/qualification/ascent-aggregate-program-output.ss"
           "t/qualification/ascent-derived-aggregate-program-output.ss"
           "t/qualification/ascent-lattice-session-output.ss"
           "t/qualification/ascent-integrated-corpus-output.ss"
           "t/qualification/ascent-eqrel-program-output.ss"
           "t/qualification/ascent-byods-query-output.ss"
           "t/model/source-closure.ss"
           "t/model/study.ss"))
        ;; Output-dir precedence binds the executable to this current Library,
        ;; even when GERBIL_PATH also contains an older installed ASCENT.
        (let ((source "t/model/study.ss")
              (options [output-dir: package-library
                        output-file: (path-expand "dsl-closure" test-cache)
                        parallel: #t verbose: #t invoke-gsc: #t static: #t
                        gsc-options: gerbil-ascent-compiler-options]))
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
