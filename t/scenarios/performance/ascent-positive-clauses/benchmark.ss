;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

((benchmarkKind . scenario-e2e)
 (max_total . 1000us)
 (target_total . 700us)
 (regression_budget . 300us)
 (expected_over_input_budget . 0us)
 (sampleCount . 20)
 (targetRationale . "Measure evaluation of a declared Scheme program with an if guard, a for generator, and recursive reachability.")
 (unit . "us")
 (sourcePath . "t/scenarios/performance/ascent-positive-clauses/benchmark.ss")
 (rule . GERBIL-SCHEME-AGENT-R031)
 (feature . ascent-positive-clauses)
 (optimizationFocus . "ordered POO clause evaluation and semi-naive relation deltas")
 (inputShape . "three ternary edge rows and three node rows")
 (expectedOutcome . "one hot row, six choices, three generated rows, and four reachable pairs")
 (expectedRepair . "reduce repeated clause dispatch while retaining the Foundation POO declaration boundary")
 (baseline . "repeat deep Foundation contract validation and POO slot lookup on every evaluation")
 (candidate . "validate POO declarations at construction and read private clause plans once per evaluation")
 (measurementPhases candidate-clauses assert-semantic-gate assert-time-gate)
 (tags poo ascent guard generator performance))
