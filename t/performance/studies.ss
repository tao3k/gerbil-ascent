;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Declaration only: compile inputs, native entry and fixed scenario arguments.
(export (struct-out study) performance-studies find-study)
(defstruct study (name modules entry scenarios native? arguments keep-going? receipt-suffix) final: #t)
(def performance-studies
  (list
    (make-study 'uf-compact-query
      '("core/relation-view" "t/performance/uf-compact-query/reference-relation-view" "t/performance/uf-compact-query/fixture" "t/performance/paired-study" "t/performance/uf-compact-query/runner")
      "t/performance/uf-compact-query/runner.ss"
      '("component-query" "point-tail" "point-absent" "grouped" "reordered" "wide" "wide-rows" "partial" "partial-absent" "conflict" "single-axis" "unindexed" "small" "repeated-small" "capture" "tiny-capture")
      #t '(scenario receipt) #f ".ss")
    (make-study 'uf-initialization
      '("core/relation-view" "t/performance/uf-initialization/reference-relation-view" "t/performance/uf-initialization/fixture" "t/performance/paired-study" "t/performance/uf-initialization/runner")
      "t/performance/uf-initialization/runner.ss"
      '("point-tail" "point-absent" "grouped" "reordered" "wide" "conflict" "single-axis" "unindexed" "small" "repeated-small" "capture" "tiny-capture")
      #t '(scenario receipt) #f ".ss")
    (make-study 'uf-plan
      '("core/relation-view" "t/performance/uf-plan/reference-relation-view" "t/performance/uf-plan/fixture" "t/performance/paired-study" "t/performance/uf-plan/runner")
      "t/performance/uf-plan/runner.ss"
      '("grouped" "reordered" "wide" "conflict" "single-axis" "unindexed" "small" "repeated-small" "capture" "tiny-capture")
      #t '(scenario receipt) #f ".ss")
    (make-study 'uf-query
      '("core/relation-view" "t/performance/uf-query/reference-relation-view" "t/performance/uf-query/fixture" "t/performance/paired-study" "t/performance/uf-query/runner")
      "t/performance/uf-query/runner.ss"
      '("grouped" "reordered" "wide" "conflict" "single-axis" "unindexed" "small" "capture")
      #t '(scenario receipt) #f ".ss")
    (make-study 'uf-weighted
      '("core/relation-view" "table/trrel-uf" "t/performance/uf-weighted/reference-relation-view" "t/performance/uf-weighted/reference-trrel-uf" "t/performance/uf-weighted/fixture" "t/performance/paired-study" "t/performance/uf-weighted/runner")
      "t/performance/uf-weighted/runner.ss"
      '("heavy" "grouped" "left-query" "right-query" "dense" "sparse" "small")
      #t '(scenario receipt) #f ".ss")
    (make-study 'uf-membership
      '("core/relation-view" "t/performance/uf-membership/reference-relation-view" "t/performance/uf-membership/fixture" "t/performance/paired-study" "t/performance/uf-membership/runner")
      "t/performance/uf-membership/runner.ss"
      '("membership" "difference" "grouped" "export" "unindexed" "small" "absent")
      #t '(scenario receipt) #f ".ss")
    (make-study 'source-cut
      '("program/source-cut" "t/performance/source-cut-benchmark")
      "t/performance/source-cut-benchmark.ss" '("untouched" "wide-batch" "small")
      #f '(scenario receipt) #f "-final.sexp")
    (make-study 'actor-admission
      '("program/actor-round" "t/performance/actor-admission/reference" "t/performance/actor-coordinator/reference" "t/performance/actor-admission-benchmark" "t/performance/actor-admission-native")
      "t/performance/actor-admission-native.ss" '("wide" "backlog" "small")
      #t '(scenario library receipt baseline) #f ".sexp")
    (make-study 'index-projection
      '("table/funs" "table/access" "t/performance/index-projection/reference-funs" "t/performance/index-projection/reference-access" "t/performance/index-projection-benchmark")
      "t/performance/index-projection-benchmark.ss" '("wide" "compact" "fallback" "small")
      #t '(scenario library receipt) #f ".sexp")
    (make-study 'expression-plan
      '("core/expression-plan" "core/positive-plan" "program/component-plan" "program/evaluate" "t/performance/expression-plan/scope-reference" "t/performance/expression-plan/reference" "t/performance/expression-plan/analysis-reference" "t/performance/expression-plan/planning-reference" "t/performance/expression-plan/evaluate-reference" "t/performance/expression-plan/input" "t/performance/expression-plan-benchmark")
      "t/performance/expression-plan-benchmark.ss" '("lower-deep" "lower-scope" "lower-small" "lower-pure" "lower-pure-wide" "deep" "scope" "chain" "wide" "pure" "small")
      #t '(scenario library receipt) #t ".sexp")
    (make-study 'proof-replay
      '("candidate/provenance" "t/performance/proof-replay/input" "t/performance/proof-replay/reference" "t/performance/proof-replay-benchmark")
      "t/performance/proof-replay-benchmark.ss" '("copy" "duplicate" "source" "small")
      #t '(scenario library receipt) #f ".sexp")
    (make-study 'typed-domain
      '("program/operator" "program/higher-order" "t/performance/typed-domain/operator-reference" "t/performance/typed-domain/reference" "t/performance/typed-domain-benchmark")
      "t/performance/typed-domain-benchmark.ss" '("ordered" "permuted" "small")
      #t '(scenario library receipt) #f ".sexp")
    (make-study 'nonmembership-index
      '("candidate/nonmembership" "t/performance/nonmembership-index/input" "t/performance/nonmembership-index/reference" "t/performance/nonmembership-index-benchmark")
      "t/performance/nonmembership-index-benchmark.ss" '("wide" "uncovered" "small")
      #t '(scenario library receipt) #f ".sexp")
    (make-study 'temporal-projection
      '("temporal/lens" "t/performance/temporal-projection/reference" "t/performance/temporal-projection-benchmark")
      "t/performance/temporal-projection-benchmark.ss" '("chain" "fan" "complete" "empty")
      #t '(scenario library receipt) #f ".sexp")
    (make-study 'uf-commit
      '("table/trrel-uf" "t/performance/uf-commit/reference" "t/performance/uf-commit-benchmark")
      "t/performance/uf-commit-benchmark.ss" '("partial" "cycle" "lifecycle" "dag" "duplicate" "islands")
      #t '(scenario library receipt) #f ".sexp")
    (make-study 'slot-projection
      '("core/positive-plan" "t/performance/slot-projection/reference" "t/performance/slot-projection-benchmark")
      "t/performance/slot-projection-benchmark.ss" '("sparse" "reverse" "repeat" "full" "below-boundary" "boundary" "small" "empty" "single")
      #t '(scenario library receipt) #f ".sexp")
    (make-study 'stratified-model
      '("candidate/closure-index" "candidate/stratified-proof" "candidate/stratified-producer" "t/performance/stratified-model/reference-proof" "t/performance/stratified-model/reference-producer" "t/performance/stratified-model-benchmark")
      "t/performance/stratified-model-benchmark.ss" '("source" "derived" "relations" "duplicates" "small")
      #t '(scenario library receipt) #f ".sexp")
    (make-study 'operator-scope
      '("program/operator-descriptor" "program/operator-analysis" "program/operator-measurement" "program/operator-reference" "program/operator" "t/performance/operator-scope/reference" "t/performance/operator-scope-benchmark")
      "t/performance/operator-scope-benchmark.ss" '("scaled-diamond" "small")
      #t '(scenario library receipt) #f ".sexp")
    (make-study 'provenance-maintenance
      '("candidate/provenance-maintenance" "candidate/provenance-graph" "t/performance/provenance-maintenance/reference" "t/performance/provenance-maintenance-benchmark")
      "t/performance/provenance-maintenance-benchmark.ss" '("wide" "duplicates" "read" "small")
      #t '(scenario library receipt) #f ".sexp")
    (make-study 'component-workspace
      '("program/index" "program/component-worker" "program/positive-components" "t/performance/component-workspace/reference-index" "t/performance/component-workspace/reference-worker" "t/performance/component-workspace/reference-coordinator" "t/performance/component-workspace-benchmark")
      "t/performance/component-workspace-benchmark.ss" '("scan" "recursive" "indexed" "small")
      #t '(scenario library receipt) #f ".sexp")
    (make-study 'component-scope
      '("program/component-plan" "program/component-worker" "program/positive-components" "program/evaluate" "t/performance/component-scope/reference" "t/performance/component-scope/fixture" "t/performance/component-scope-benchmark")
      "t/performance/component-scope-benchmark.ss" '("sparse-plan" "multihead-plan" "closure-one" "closure-four" "small")
      #f '(scenario library receipt) #f ".sexp")
    (make-study 'strata-preflight
      '("core/rule-semantics" "program/actor-round" "program/positive-components" "program/planning" "program/evaluate" "t/performance/strata-preflight/reference-semantics" "t/performance/strata-preflight/reference-planning" "t/performance/strata-preflight/reference-evaluate" "t/performance/strata-preflight/fixture" "t/performance/strata-preflight-benchmark")
      "t/performance/strata-preflight-benchmark.ss" '("positive" "negation" "aggregate" "lattice" "cold" "warm" "small")
      #f '(scenario library receipt) #f ".sexp")
    (make-study 'index-build
      '("table/funs" "table/access" "program/index" "program/evaluate" "t/performance/index-build/reference-funs" "t/performance/index-build/reference-access" "t/performance/index-build/reference-index" "t/performance/index-build/reference-evaluate" "t/performance/index-build/fixture" "t/performance/index-build-benchmark")
      "t/performance/index-build-benchmark.ss" '("scalar-dense" "scalar-unique" "composite-dense" "composite-unique" "empty" "small" "solve")
      #f '(scenario library receipt) #f ".sexp")
    (make-study 'source-log
      '("core/positive-plan" "program/actor-round" "program/source-log" "program/evaluate" "program/session" "t/performance/source-log/reference-update-selection" "t/performance/source-log/reference-reuse" "t/performance/source-log/reference-evaluate" "t/performance/source-log/reference-session" "t/performance/source-log/fixture" "t/performance/source-log-benchmark")
      "t/performance/source-log-benchmark.ss" '("join" "equal" "pending" "mismatch" "update" "appended-update" "small")
      #f '(scenario library receipt) #f ".sexp")
    (make-study 'selected-activation
      '("program/activation" "program/update-selection" "program/reuse" "program/evaluate" "t/performance/selected-activation/reference-selection" "t/performance/selected-activation/reference-reuse" "t/performance/selected-activation/reference-evaluate" "t/performance/selected-activation/fixture" "t/performance/selected-activation-benchmark")
      "t/performance/selected-activation-benchmark.ss" '("sparse" "partial" "all" "update" "lifecycle" "small")
      #f '(scenario library receipt) #f ".sexp")
    (make-study 'storage-batch
      '("program/admission" "program/evaluate" "t/performance/storage-batch/reference" "t/performance/storage-batch/reference-evaluate" "t/performance/storage-batch/fixture" "t/performance/storage-batch-benchmark")
      "t/performance/storage-batch-benchmark.ss" '("batch" "wide" "duplicates" "engine" "single" "empty" "engine-small")
      #f '(scenario library receipt) #f ".sexp")
    (make-study 'index-sharing
      '("table/index-sharing" "t/performance/index-sharing/reference" "t/performance/index-sharing-benchmark")
      "t/performance/index-sharing-benchmark.ss" '("wide" "sparse" "small" "scalar" "empty")
      #t '(scenario library receipt) #f ".sexp")
    (make-study 'index-entry
      '("program/index" "program/evaluate" "t/performance/index-entry/reference" "t/performance/index-entry/reference-evaluate" "t/performance/index-entry/fixture" "t/performance/index-entry-benchmark")
      "t/performance/index-entry-benchmark.ss" '("all" "delta" "advance" "scalar" "cold" "solve-wide" "solve-small")
      #f '(scenario library receipt) #f ".sexp")
    (make-study 'rule-bindings
      '("core/rule-bindings" "core/positive-plan" "program/evaluate" "t/performance/rule-bindings/reference" "t/performance/rule-bindings/reference-positive" "t/performance/rule-bindings/reference-evaluate" "t/performance/rule-bindings/fixture" "t/performance/rule-bindings-benchmark")
      "t/performance/rule-bindings-benchmark.ss" '("call-two" "call-six" "bind-wide" "guards" "patterns" "small")
      #f '(scenario library receipt) #f ".sexp")
    (make-study 'finite-replay
      '("candidate/funs" "candidate/finite-evidence" "candidate/types" "candidate/datum" "t/performance/finite-replay/reference-funs" "t/performance/finite-replay/reference" "t/performance/finite-replay-benchmark")
      "t/performance/finite-replay-benchmark.ss" '("wide" "duplicates" "small" "constant")
      #f '(scenario library) #f ".sexp")
    (make-study 'bounded-datum
      '("candidate/datum" "candidate/types" "candidate/provenance" "candidate/provenance-graph" "t/performance/bounded-datum/reference" "t/performance/bounded-datum/reference-graph" "t/performance/bounded-datum-benchmark")
      "t/performance/bounded-datum-benchmark.ss" '("kernel" "verifier")
      #f '(scenario library) #f ".sexp")
    (make-study 'provenance-index
      '("candidate/provenance-graph" "t/performance/provenance-index/reference" "t/performance/provenance-index-benchmark")
      "t/performance/provenance-index-benchmark.ss" '("small" "wide" "duplicates")
      #f '(scenario library) #f ".sexp")
    (make-study 'update-dependencies
      '("core/dependency-graph" "core/rule-semantics" "program/planning" "program/update-selection" "t/performance/update-dependencies/reference" "t/performance/update-dependencies-benchmark")
      "t/performance/update-dependencies-benchmark.ss" '("chain-changed" "chain-unchanged" "wide-changed" "wide-unchanged")
      #f '(scenario library) #f ".sexp")
    (make-study 'scalar-index
      '("table/funs" "table/access" "core/positive-plan" "program/index" "program/evaluate" "t/performance/scalar-index/reference-access" "t/performance/scalar-index-benchmark")
      "t/performance/scalar-index-benchmark.ss" '("single-first" "single-later" "composite-control" "tiny-control")
      #f '(scenario library) #f ".sexp")
    (make-study 'finite-mapping
      '("table/provider" "table/storage" "table/access" "program/types" "program/objects" "program/scheme-checked" "program/index" "program/evaluate" "program/session" "program/update-selection" "t/performance/finite-mapping/reference-types" "t/performance/finite-mapping/reference-objects" "t/performance/finite-mapping/reference" "t/performance/finite-mapping-benchmark")
      "t/performance/finite-mapping-benchmark.ss" '("narrow-rows" "wide-rows" "wide-view" "source-control" "canonical-provider")
      #f '(scenario library) #f ".sexp")
  ))
(def (find-study name)
  (or (find (lambda (entry) (eq? name (study-name entry))) performance-studies)
      (error "unknown performance study" name)))
