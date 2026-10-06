;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Generated with :asp-gerbil-scheme/benchmark-api#make-benchmark-fixture.
((benchmarkKind . scenario-e2e)
(max_total . 999ms)
(target_total . 500ms)
(regression_budget . 499ms)
(expected_over_input_budget . 0ms)
(targetRationale . "Diagnostic pair wall time; relative CPU admission covers complete physical index lifecycle")
(sampleCount . 50)
(rule . ASCENT-INDEX-PROJECTION)
(feature . physical-index-lifecycle)
(optimizationFocus . "Hoist shape dispatch and immutable projection offsets out of row loops")
(inputShape . "Dense wide ordered keys plus compact arbitrary repeated and small controls")
(expectedOutcome . "Exact build-extend-lookup row order from independent direct projection")
(measurementPhases build extend lookup independent-oracle)
(tags native paired index expression)
(baseline . 0aae58cd770590c0b22b0b6fa29103f97bf9bf9d)
(scenarios (wide (rows . 4096) (batch . 64) (width . 64) (columns 0 8 16 24 32 40 48 56) (repetitions . 4) (cpuRatio . 4/5) (cpuOverheadSeconds . 0) (allocationOverheadBytes . 4096) (minimumCpuWins . 35)) (compact (rows . 4096) (batch . 64) (width . 4) (columns 0 2) (repetitions . 4) (cpuRatio . 21/20) (cpuOverheadSeconds . 1/50000) (allocationOverheadBytes . 4096) (minimumCpuWins . 0)) (fallback (rows . 4096) (batch . 64) (width . 64) (columns 57 0 57 2) (repetitions . 4) (cpuRatio . 21/20) (cpuOverheadSeconds . 1/50000) (allocationOverheadBytes . 4096) (minimumCpuWins . 0)) (small (rows . 4) (batch . 2) (width . 4) (columns 0 2) (repetitions . 64) (cpuRatio . 21/20) (cpuOverheadSeconds . 1/50000) (allocationOverheadBytes . 1024) (minimumCpuWins . 0)))
)
