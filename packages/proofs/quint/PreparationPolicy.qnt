// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Generated from ExecutionPolicy.lean (PreparationPolicy); formal CI checks exact rendering.
module PreparationPolicy {
  pure def preparation_observation_complete(failed_jobs: int, changed_inputs: int, negative_allocations: int, observer_ran: bool): bool = (observer_ran and ((failed_jobs == 0) and ((changed_inputs == 0) and (negative_allocations == 0))))
  pure def preparation_non_regression(baseline_ns: int, candidate_ns: int): bool = not((baseline_ns < candidate_ns))
  pure def preparation_latch_failure(prior_failure: bool, new_failure: bool): bool = (prior_failure or new_failure)
  pure def preparation_admitted(baseline_ns: int, candidate_ns: int, warm_rebuilds: int, unresolved: int, matched: bool, complete: bool, cost_accounted: bool): bool = (matched and (complete and (cost_accounted and ((warm_rebuilds == 0) and ((unresolved == 0) and not((baseline_ns < candidate_ns)))))))
}
