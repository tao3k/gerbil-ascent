# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
# Generated from ExecutionPolicy.lean (PreparationPolicy); formal CI checks exact rendering.

def preparation_observation_complete(failed_jobs, changed_inputs, negative_allocations, observer_ran):
    return (observer_ran and ((failed_jobs == 0) and ((changed_inputs == 0) and (negative_allocations == 0))))

def preparation_non_regression(baseline_ns, candidate_ns):
    return (not (baseline_ns < candidate_ns))

def preparation_latch_failure(prior_failure, new_failure):
    return (prior_failure or new_failure)

def preparation_admitted(baseline_ns, candidate_ns, warm_rebuilds, unresolved, matched, complete, cost_accounted):
    return (matched and (complete and (cost_accounted and ((warm_rebuilds == 0) and ((unresolved == 0) and (not (baseline_ns < candidate_ns)))))))
