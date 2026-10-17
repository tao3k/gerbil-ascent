#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/build-script defbuild-script)
        (only-in :std/make make-clean)
        (only-in :std/source this-source-file)
        (only-in :gerbil/runtime/loader add-load-path!)
        (only-in "bindings/artifact.ss"
                 source-snapshot artifact-receipt! artifact-invalidated-modules clean-compiled-resources!)
        (only-in :asp-gerbil-scheme/building-api
                 asp-gerbil-scheme-package-spec!
                 asp-gerbil-scheme-library-package-prototype))


(def gerbil-ascent-library-modules
  '("core/ordered-pair-set"
    "core/binary-relation"
    "core/relation-view"
    "core/finite-flow"
    "table/expression"
    "table/funs"
    "table/eqrel"
    "table/trrel"
    "table/trrel-uf"
    "table/index-sharing"
    "table/provider"
    "table/access"
    "table/storage"
    "table/interface"
    "program/types"
    "program/objects"
    "program/aggregators"
    "program/syntax"
    "program/planning"
    "core/ordered-call"
    "core/expression-plan"
    "core/execution-policy"
    "core/descriptor-stream"
    "core/actor-envelope"
    "core/index-publication"
    "core/positive-certificate"
    "core/positive-plan"
    "program/index"
    "program/scheme-checked"
    "program/scheme-snapshot"
    "program/scheme-query"
    "program/scheme-admit"
    "program/scheme-session"
    "program/scheme-admission"
    "program/scheme-language"
    "program/operator-descriptor"
    "program/operator-analysis"
    "program/operator-measurement"
    "program/operator-reference"
    "program/operator-lowering"
    "program/operator"
    "program/finite-arithmetic"
    "program/higher-order"
    "program/operator-change"
    "program/operator-session"
    "core/scc-state"
    "core/dependency-graph"
    "core/rule-bindings"
    "core/rule-semantics"
    "program/analysis"
    "program/evidence-dag"
    "program/trajectory"
    "program/summary"
    "program/admission"
    "program/view-replay"
    "program/view-state"
    "program/lattice-frontier"
    "program/initialization"
    "program/source-snapshot"
    "program/source-state"
    "program/result"
    "program/source-log"
    "program/activation"
    "program/update-selection"
    "program/reuse"
    "program/actor-round"
    "program/component-plan"
    "program/component-worker"
    "program/positive-components"
    "program/execution-publication"
    "program/round-workspace"
    "program/execution-control"
    "program/evaluate"
    "program/session"
    "program/source-cut"
    "program/actor-session"
    "program/interface"
    "applications/steensgaard"
    "applications/polonius"
    "applications/polonius-paths"
    "applications/finite-flow-program"
    "applications/taint-paths"
    "applications/scoped-witness"
    "applications/scoped-reachability-mask"
    "applications/scoped-composition"
    "applications/movie-cast-query"
    "applications/domain-evidence"
    "core/binary-program"
    "candidate/closure"
    "candidate/datum"
    "candidate/types"
    "candidate/certificate-limits"
    "candidate/program-identity"
    "candidate/program"
    "candidate/funs"
    "candidate/grounding-plan"
    "candidate/proof-frame"
    "candidate/reduction-plan"
    "candidate/finite-plan"
    "candidate/provenance"
    "candidate/provenance-graph"
    "candidate/support-dependencies"
    "candidate/support-cut"
    "candidate/support-height"
    "candidate/provenance-maintenance"
    "candidate/annotations"
   "candidate/stratified-provenance"
    "candidate/nonmembership"
    "candidate/finite-evidence"
    "candidate/closure-index"
    "candidate/stratified-plan"
    "candidate/stratified-proof"
    "candidate/stratified-producer"
    "candidate/reasoning"
    "candidate/evidence-store"
    "candidate/feedback"
    "candidate/withholding"
    "candidate/withdrawal-session"
    "temporal/graph"
    "temporal/value"
    "temporal/projection"
    "temporal/lens"
    "interface/request"
    "interface/rule-source"
    "evidence/declaration"
    "interface/closed-source"
    "interface/closed-evidence"
    "interface/dsl-source"
    "interface/evidence-module"
    "interface/value-graph"
    "evidence/interface"
    "evidence/execution"
    "evidence/module"
    "t/qualification/evidence-api-module"
    "interface/engine-api"))

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
(def (build-library . args)
  (def (run spec)
    (defbuild-script spec
      optimize: (not (equal? (getenv "GERBIL_BUILD_OPTIMIZE" "1") "0")))
    (apply main args))
  (def spec (gerbil-ascent-build-spec))
  (def (executable? target)
    (and (pair? target) (eq? (car target) exe:)))
  (if (or (null? args) (equal? (car args) "compile"))
    (begin
      (run (filter (lambda (target) (not (executable? target))) spec))
      ;; gsc -link regenerates shared dependency C files. Each standard make
      ;; call drains its pending jobs before the next executable starts.
      (for-each (lambda (target)
                  (displayln "... link target " (cadr target))
                  (run [target]))
                (filter executable? spec)))
    (run spec)))

(def (main . args)
  (let* ((build? (or (null? args) (equal? (car args) "compile")))
         (root (path-directory (this-source-file)))
         (modules (append gerbil-ascent-library-modules
                          '("interface/c-api" "interface/runtime" "interface/entry" "interface/develop")))
         (before (and build? (source-snapshot root modules))))
    (add-load-path! (path-expand "lib" (gerbil-path)))
    (when build?
      (let (invalidated (artifact-invalidated-modules root modules before))
        (if invalidated
          (unless (null? invalidated)
            (clean-compiled-resources! (path-expand "lib/gerbil-ascent" (gerbil-path)) invalidated)
            (make-clean
              (filter (lambda (spec)
                        (member (if (string? spec) spec (cadr spec)) invalidated))
                      (gerbil-ascent-build-spec)) srcdir: root))
          (begin
            (clean-compiled-resources! (path-expand "lib/gerbil-ascent" (gerbil-path)) modules)
            (build-library "clean")))))
    (apply build-library args)
    (when build? (artifact-receipt! root modules before))))
