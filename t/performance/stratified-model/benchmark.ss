;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Generated with :asp-gerbil-scheme/benchmark-api#make-benchmark-fixture.
((benchmarkKind . scenario-e2e)
(max_total . 999ms)
(target_total . 500ms)
(regression_budget . 499ms)
(expected_over_input_budget . 0ms)
(targetRationale . "Diagnostic whole checked pair wall time; relative CPU includes replay production and verification")
(sampleCount . 50)
(rule . ASCENT-STRATIFIED-MODEL)
(feature . proof-production)
(optimizationFocus . "Invocation-owned verified closure membership and source occurrence positions")
(inputShape . "Large source and derived proofs plus many relations duplicate sources and small controls")
(expectedOutcome . "Byte/data-equal ordered proofs and independent frozen checker acceptance")
(measurementPhases finite-replay produce independent-verify)
(tags native paired proof model)
(baseline . 5e549ce8d17c3fd942cdb50eb36cee825c06f795)
(scenarios (source (rows . 1024) (distinct . 1024) (relations . 1) (derived? . #f) (cpuRatio . 4/5) (cpuOverheadSeconds . 0) (allocationRatio . 5/4) (allocationOverheadBytes . 8192) (minimumCpuWins . 35)) (derived (rows . 512) (distinct . 512) (relations . 1) (derived? . #t) (cpuRatio . 4/5) (cpuOverheadSeconds . 0) (allocationRatio . 5/4) (allocationOverheadBytes . 8192) (minimumCpuWins . 35)) (relations (rows . 8) (distinct . 8) (relations . 48) (derived? . #f) (cpuRatio . 21/20) (cpuOverheadSeconds . 3/100000) (allocationRatio . 5/4) (allocationOverheadBytes . 8192) (minimumCpuWins . 0)) (duplicates (rows . 512) (distinct . 64) (relations . 1) (derived? . #f) (cpuRatio . 21/20) (cpuOverheadSeconds . 3/100000) (allocationRatio . 5/4) (allocationOverheadBytes . 8192) (minimumCpuWins . 0)) (small (rows . 4) (distinct . 4) (relations . 1) (derived? . #f) (cpuRatio . 21/20) (cpuOverheadSeconds . 3/100000) (allocationRatio . 1) (allocationOverheadBytes . 8192) (minimumCpuWins . 0)))
)
