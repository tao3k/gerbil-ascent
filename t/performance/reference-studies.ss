;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(export (struct-out reference-study) reference-studies find-reference-study)
(defstruct reference-study (name modules entry build-seconds run-seconds results) final: #t)
(def reference-studies
  (list
    (make-reference-study 'binding
      '("core/dependency-graph" "core/rule-semantics" "program/objects" "program/evaluate" "t/qualification/ascent-binding-reference-fixture" "t/qualification/ascent-binding-reference-evaluate" "t/qualification/ascent-index-program-fixture")
      "t/performance/binding-benchmark.ss" 150 120 6)
    (make-reference-study 'strata
      '("core/dependency-graph" "core/rule-semantics" "t/qualification/ascent-strata-fixture")
      "t/performance/strata-benchmark.ss" 60 90 4)
    (make-reference-study 'size
      '("program/evaluate" "t/qualification/ascent-size-reference-evaluate")
      "t/performance/size-benchmark.ss" 90 150 3)
    (make-reference-study 'multi-frontier
      '("program/evaluate" "t/qualification/ascent-multi-frontier-reference-evaluate")
      "t/performance/multi-frontier-benchmark.ss" 90 150 4)
    (make-reference-study 'set-size
      '("program/evaluate" "t/qualification/ascent-set-size-reference-evaluate")
      "t/performance/set-size-benchmark.ss" 90 150 3)
    (make-reference-study 'set-batch
      '("table/storage" "t/qualification/ascent-set-batch-reference")
      "t/performance/set-batch-benchmark.ss" 90 150 6)
    (make-reference-study 'set-emit
      '("program/evaluate" "t/qualification/ascent-set-emit-reference-evaluate")
      "t/performance/set-emit-benchmark.ss" 90 400 6)
    (make-reference-study 'set-emit-allocation
      '("program/evaluate" "t/qualification/ascent-set-emit-reference-evaluate")
      "t/performance/set-emit-allocation.ss" 90 150 6)
    (make-reference-study 'set-source-allocation
      '("program/admission" "program/evaluate" "t/qualification/ascent-set-source-reference-evaluate")
      "t/performance/set-source-allocation.ss" 90 150 6)
    (make-reference-study 'positive-plan
      '("core/positive-plan" "program/index" "program/actor-round" "program/evaluate" "t/qualification/ascent-positive-plan-reference-analysis" "t/qualification/ascent-positive-plan-reference-evaluate")
      "t/performance/positive-plan-benchmark.ss" 150 180 7)
    (make-reference-study 'workspace
      '("core/positive-plan" "program/evaluate" "t/qualification/ascent-workspace-reference-analysis" "t/qualification/ascent-workspace-reference-positive" "t/qualification/ascent-workspace-reference-evaluate")
      "t/performance/workspace-benchmark.ss" 150 180 9)
    (make-reference-study 'materialization
      '("core/binary-relation" "table/expression" "t/qualification/ascent-materialization-reference")
      "t/performance/materialization-benchmark.ss" 150 180 8)
    (make-reference-study 'index-lifecycle
      '("table/funs" "table/access" "program/evaluate" "t/qualification/ascent-index-reference-funs" "t/qualification/ascent-index-reference-provider" "t/qualification/ascent-index-reference-evaluate")
      "t/performance/index-lifecycle-benchmark.ss" 150 30 7)
    (make-reference-study 'result
      '("program/result" "program/evaluate" "t/qualification/ascent-result-reference-evaluate")
      "t/performance/result-benchmark.ss" 150 30 10)
  ))
(def (find-reference-study name)
  (or (find (lambda (entry) (eq? name (reference-study-name entry))) reference-studies)
      (error "unknown reference study" name)))
