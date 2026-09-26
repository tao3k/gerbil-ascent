;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

((benchmarkKind . scenario-e2e)
 (max_total . 2000us)
 (target_total . 1000us)
 (regression_budget . 1000us)
 (expected_over_input_budget . 0us)
 (sampleCount . 20)
 (targetRationale . "Evaluate the declared two-hop program over a 50-edge chain with bound-column index access.")
 (unit . "us")
 (sourcePath . "t/scenarios/performance/ascent-indexed-joins/benchmark.ss")
 (rule . GERBIL-SCHEME-AGENT-R031)
 (feature . ascent-indexed-joins)
 (optimizationFocus . "bound-column hash access for repeated joins")
 (inputShape . "50 binary edges and 49 two-hop result rows")
 (expectedOutcome . "49 exact two-hop rows without recursive transitive closure")
 (expectedRepair . "keep index construction outside repeated row probes")
 (baseline . "scan every edge row for each bound join value")
 (candidate . "cache a hash index by relation, bound columns and table generation")
 (measurementPhases candidate-clauses assert-semantic-gate assert-time-gate)
 (tags poo ascent index join performance))
