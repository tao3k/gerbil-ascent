;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Generated with :asp-gerbil-scheme/benchmark-api#make-benchmark-fixture.
((benchmarkKind . scenario-e2e)
(max_total . 999ms)
(target_total . 500ms)
(regression_budget . 499ms)
(expected_over_input_budget . 0ms)
(targetRationale . "Pair wall time is diagnostic; relative CPU includes cold slot compilation frame allocation and native traversal")
(sampleCount . 50)
(rule . ASCENT-SLOT-PROJECTION)
(feature . compile-and-traverse)
(optimizationFocus . "Select immutable slot actions by projection shape without a width cutoff")
(inputShape . "Wide sparse reverse repeated and full keys plus former boundary small empty and single controls")
(expectedOutcome . "Equal compiled metadata action identity and native join rows from direct truth")
(measurementPhases compile allocate-frame traverse emit)
(tags native paired compiler projection)
(baseline . 5ea7fa82f33e5559dae43fe375a60795965d0832)
(scenarios (sparse (width . 2048) (shape . sparse) (repetitions . 2) (cpuRatio . 4/5) (cpuOverheadSeconds . 0) (allocationRatio . 1) (allocationOverheadBytes . 16384) (minimumCpuWins . 35)) (reverse (width . 2048) (shape . reverse) (repetitions . 2) (cpuRatio . 4/5) (cpuOverheadSeconds . 0) (allocationRatio . 1) (allocationOverheadBytes . 16384) (minimumCpuWins . 35)) (repeat (width . 1024) (shape . repeat) (repetitions . 2) (cpuRatio . 4/5) (cpuOverheadSeconds . 0) (allocationRatio . 1) (allocationOverheadBytes . 16384) (minimumCpuWins . 35)) (full (width . 2048) (shape . full) (repetitions . 2) (cpuRatio . 21/20) (cpuOverheadSeconds . 1/50000) (allocationRatio . 1) (allocationOverheadBytes . 16384) (minimumCpuWins . 0)) (below-boundary (width . 127) (shape . full) (repetitions . 8) (cpuRatio . 21/20) (cpuOverheadSeconds . 1/50000) (allocationRatio . 1) (allocationOverheadBytes . 1024) (minimumCpuWins . 0)) (boundary (width . 128) (shape . full) (repetitions . 8) (cpuRatio . 21/20) (cpuOverheadSeconds . 1/50000) (allocationRatio . 1) (allocationOverheadBytes . 1024) (minimumCpuWins . 0)) (small (width . 4) (shape . full) (repetitions . 64) (cpuRatio . 21/20) (cpuOverheadSeconds . 1/50000) (allocationRatio . 1) (allocationOverheadBytes . 1024) (minimumCpuWins . 0)) (empty (width . 32) (shape . empty) (repetitions . 32) (cpuRatio . 21/20) (cpuOverheadSeconds . 1/50000) (allocationRatio . 1) (allocationOverheadBytes . 1024) (minimumCpuWins . 0)) (single (width . 128) (shape . single) (repetitions . 8) (cpuRatio . 21/20) (cpuOverheadSeconds . 1/50000) (allocationRatio . 1) (allocationOverheadBytes . 1024) (minimumCpuWins . 0)))
)
