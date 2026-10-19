;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Test-only runtime dependencies. std/make owns their compilation order.
(import (only-in :gerbil/expander current-expander-module-import))
(export call-with-preparation-production-interfaces test-library-base test-library-dependencies performance-modules performance-contract-files performance-scenario-files preparation-retained-source? preparation-projection-roots preparation-support-roots)
;; BEGIN GENERATED PREPARATION INTERFACES
;; Gerbil still owns path normalization, module caching and expansion.
(def (call-with-preparation-production-interfaces admitted? library production thunk)
  (let ((original (current-expander-module-import))
        (interfaces
          (if admitted?
            (filter-map
              (lambda (module)
                (let (target (path-expand (string-append "gerbil-ascent/" module ".ssi") library))
                  (and (file-exists? target)
                       (cons (path-normalize (string-append module ".ss")) target))))
              production)
            [])))
    (parameterize
      ((current-expander-module-import
         (lambda (path reload?)
           (let (entry (and (not reload?) (string? path)
                           (assoc (path-normalize path) interfaces)))
             (original (if entry (cdr entry) path) reload?)))))
      (thunk))))
;; END GENERATED PREPARATION INTERFACES

;; BEGIN GENERATED PREPARATION SOURCE
;; Generated from PreparationWork.lean; formal CI compares this region.
(def (preparation-retained-source? source source-suites? source-consumers)
  (and (not (member source source-consumers))
       (or (not source-suites?) (not (string-suffix? "-test.ss" source)))))
;; END GENERATED PREPARATION SOURCE

;; BEGIN GENERATED PREPARATION ROOTS
(def (preparation-projection-roots production modules tests source-consumers production-current?)
  (append (if production-current?
            (filter (lambda (module) (not (member module production))) modules)
            modules)
          tests source-consumers))
(def (preparation-support-roots source-suites? base requested cached)
  (append (if source-suites? [] base) requested cached))
;; END GENERATED PREPARATION ROOTS

(def (performance-scenario-files)
  (let (selected (getenv "ASCENT_SS_SCENARIO" #f))
    (if selected
      (list selected)
      (filter file-exists?
        (map (lambda (name) (string-append "t/scenarios/performance/" name "/scenario.ss"))
          (filter (lambda (name) (not (member name '("ascent-binary-program" "ascent-shortest-candidates"))))
            (list-sort string<? (directory-files "t/scenarios/performance"))))))))
(def performance-modules
  '("t/performance/ascent-scenario-performance-test.ss"
    "t/performance/ascent-binary-program-performance-test.ss"
    "t/performance/ascent-shortest-candidates-performance-test.ss"))
(def (performance-contract-files)
  ;; Allocation contracts require compiled production code. Source semantic
  ;; Suites remain in t/qualification; this compiled-only Case retains its bound.
  '("t/performance/ascent-withdrawal-support-performance-test.ss"
    "t/performance/ascent-uf-plan-performance-test.ss"
    "t/performance/ascent-change-plan-performance-test.ss"
    "t/performance/ascent-source-cut-allocation-test.ss"
     "t/performance/ascent-component-index-performance-test.ss"
     "t/performance/ascent-actor-credit-performance-test.ss"
     "t/performance/ascent-trrel-uf-performance-test.ss"
     "t/performance/ascent-steensgaard-performance-test.ss"
     "t/performance/ascent-relation-view-performance-test.ss"
     "t/performance/scheme-library-lifecycle-performance-test.ss"))

(def test-library-base
  '("t/performance/library" "t/performance/ascent-ss-profile"
                            "t/scenarios/performance/ascent-table-expression/baseline"
                            "t/harness/artifact-admission" "t/model/response-projection"))
(def test-library-dependencies
  '(
    (("t/qualification/scheme-artifact-test.ss") "bindings/artifact" "build-modules")
    (("t/performance/ascent-uf-plan-performance-test.ss")
      "t/performance/uf-plan/reference-relation-view" "t/performance/uf-plan/fixture"
      "t/performance/uf-membership/reference-relation-view" "t/performance/uf-membership/fixture"
      "t/performance/paired-study" "t/performance/uf-membership/runner")
    (("t/performance/ascent-withdrawal-support-performance-test.ss")
      "t/performance/withdrawal-support/replay-reference" "t/performance/withdrawal-support/runner")
    (("t/performance/ascent-change-plan-performance-test.ss")
      "t/performance/mapping-lookup/reference" "t/performance/mapping-lookup/fixture" "t/performance/change-plan-runner")
    (("t/qualification/ascent-relation-view-test.ss" "t/performance/ascent-relation-view-performance-test.ss")
      "t/qualification/ascent-relation-view-fixture")
    (("t/qualification/ascent-callback-plan-test.ss")
      "t/performance/callback-plan/expression-reference")
    (("t/qualification/ascent-expression-plan-test.ss")
      "t/performance/expression-plan/reference" "t/performance/expression-plan/analysis-reference" "t/performance/expression-plan/planning-reference" "t/performance/expression-plan/evaluate-reference" "t/performance/expression-plan/input")
    (("t/qualification/ascent-proof-replay-test.ss")
      "t/performance/proof-replay/reference")
    (("t/qualification/ascent-typed-domain-test.ss")
      "t/performance/typed-domain/operator-reference" "t/performance/typed-domain/reference")
    (("t/qualification/ascent-nonmembership-index-test.ss")
      "t/performance/nonmembership-index/reference" "t/performance/nonmembership-index/input")
    (("t/qualification/ascent-temporal-projection-test.ss")
      "t/performance/temporal-projection/reference")
    (("t/qualification/ascent-uf-dense-test.ss")
      "t/performance/uf-dense/reference-view-replay" "t/performance/uf-dense/reference-view-state" "t/performance/uf-dense/reference-initialization" "t/performance/uf-dense/reference-evaluate" "t/performance/uf-dense/reference-trrel-uf" "t/performance/uf-dense/fixture")
    (("t/qualification/ascent-uf-weighted-test.ss")
      "t/performance/uf-weighted/reference-relation-view" "t/performance/uf-weighted/reference-trrel-uf" "t/performance/uf-weighted/fixture")
    (("t/qualification/ascent-uf-capture-test.ss")
      "t/performance/uf-capture/reference-relation-view" "t/performance/uf-capture/reference-trrel-uf" "t/performance/uf-capture/fixture")
    (("t/qualification/ascent-uf-commit-test.ss")
      "t/performance/uf-commit/reference")
    (("t/qualification/ascent-trrel-uf-test.ss" "t/performance/ascent-trrel-uf-performance-test.ss")
      "t/performance/trrel-uf/reference" "t/performance/trrel-uf/root-scan-reference")
    (("t/qualification/ascent-index-entry-test.ss")
      "t/performance/index-sharing/reference")
    (("t/qualification/ascent-index-lifecycle-test.ss")
      "t/qualification/ascent-index-reference-funs" "t/qualification/ascent-index-reference-provider" "t/qualification/ascent-positive-plan-reference-analysis" "t/qualification/ascent-index-reference-evaluate")
    (("t/qualification/scheme-finite-mapping-test.ss")
      "t/performance/finite-mapping/reference-types" "t/performance/finite-mapping/reference-objects" "t/performance/finite-mapping/reference")
    (("t/qualification/scheme-provenance-graph-test.ss")
      "t/performance/provenance-index/reference" "t/performance/provenance-maintenance/reference")
    (("t/qualification/scheme-bounded-datum-test.ss")
      "t/performance/bounded-datum/reference")
    (("t/qualification/ascent-actor-credit-test.ss" "t/performance/ascent-actor-credit-performance-test.ss")
      "t/performance/actor-credit/reference" "t/performance/actor-credit/coordinator-reference" "t/performance/actor-credit/fixture")
    (("t/qualification/ascent-component-index-test.ss" "t/performance/ascent-component-index-performance-test.ss" "t/qualification/ascent-actor-credit-test.ss" "t/performance/ascent-actor-credit-performance-test.ss")
      "t/performance/component-index/reference" "t/performance/component-index/coordinator-reference" "t/performance/component-index/fixture")
    (("t/qualification/ascent-positive-components-test.ss")
      "t/performance/component-scope/reference" "t/performance/component-scope/fixture")
    (("t/qualification/ascent-strata-preflight-test.ss")
      "t/performance/strata-preflight/reference-semantics" "t/performance/strata-preflight/reference-planning" "t/performance/strata-preflight/reference-evaluate" "t/performance/strata-preflight/fixture")
    (("t/qualification/ascent-index-build-test.ss")
      "t/performance/index-build/reference-funs" "t/performance/index-build/reference-access" "t/performance/index-build/reference-index" "t/performance/index-build/reference-evaluate" "t/performance/index-build/fixture")
    (("t/qualification/ascent-stratified-proof-test.ss")
      "t/performance/stratified-model/reference-proof" "t/performance/stratified-model/reference-producer")
    (("t/qualification/ascent-source-log-test.ss")
      "t/performance/source-log/reference-update-selection" "t/performance/source-log/reference-reuse" "t/performance/source-log/reference-evaluate" "t/performance/source-log/reference-session" "t/performance/source-log/fixture")
    (("t/qualification/ascent-selected-activation-test.ss")
      "t/performance/selected-activation/reference-selection" "t/performance/selected-activation/reference-reuse" "t/performance/selected-activation/reference-evaluate" "t/performance/selected-activation/fixture")
    (("t/qualification/ascent-storage-batch-test.ss")
      "t/performance/storage-batch/reference" "t/performance/storage-batch/reference-evaluate" "t/performance/storage-batch/fixture")
    (("t/qualification/ascent-relation-view-test.ss" "t/qualification/ascent-index-entry-test.ss" "t/qualification/ascent-component-index-test.ss" "t/performance/ascent-component-index-performance-test.ss" "t/performance/ascent-relation-view-performance-test.ss")
      "t/performance/index-entry/reference" "t/performance/index-entry/reference-evaluate" "t/performance/index-entry/fixture")
    (("t/qualification/ascent-rule-bindings-test.ss")
      "t/performance/rule-bindings/reference" "t/performance/rule-bindings/reference-positive" "t/performance/rule-bindings/reference-evaluate" "t/performance/rule-bindings/fixture")
    (("t/qualification/scheme-finite-replay-test.ss")
      "t/performance/finite-replay/reference-funs" "t/performance/finite-replay/reference")
  ))
