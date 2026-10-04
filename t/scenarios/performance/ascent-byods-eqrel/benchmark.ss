;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

((benchmarkKind . scenario-e2e)
 (max_total . 1000us)
 (target_total . 700us)
 (regression_budget . 300us)
 (expected_over_input_budget . 0us)
 (sampleCount . 1000)
 (targetRationale . "Materialize the equivalence closure of a twenty-edge chain from a predeclared POO program.")
 (unit . "us")
 (sourcePath . "t/scenarios/performance/ascent-byods-eqrel/benchmark.ss")
 (rule . GERBIL-SCHEME-AGENT-R031)
 (feature . ascent-byods-eqrel)
 (optimizationFocus . "incremental component union and fact materialization")
 (inputShape . "twenty binary edges and 441 equivalence facts")
 (expectedOutcome . "the complete 21-node equivalence closure")
 (expectedRepair . "replace repeated whole-table scans with a component index")
 (baseline . "scan all materialized pairs for every inserted edge")
 (candidate . "maintain component membership and emit only new cross-component pairs")
 (measurementPhases candidate-clauses assert-semantic-gate assert-time-gate)
 (tags poo ascent byods eqrel performance))
