# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Receipt projection; decisions come from the Lean-generated policy.

This is not a source-refinement proof of the collector, SDK or decoder.
Cost coverage means returning command wall/CPU observations, not a source-work bound.
Cold expansion and declaration-allocation refinement remain separate open obligations.
"""
import math

from .preparation_policy import (
    preparation_admitted, preparation_latch_failure, preparation_non_regression,
)


def unresolved_failures(ledger):
    if ledger['schema'] != 'ascent.preparation-regressions.v1':
        raise ValueError('unknown preparation regression ledger')
    result = []
    for row in ledger['records']:
        # A later faster measurement is not a resolution certificate.
        if row['resolution'] is not None:
            raise ValueError('source-bound regression resolutions are not implemented')
        for key in ('baseline_ns', 'candidate_ns'):
            if len(row[key]) != 2 or any(type(n) is not int or n < 0 for n in row[key]):
                raise ValueError('expected both nonnegative historical samples')
        if not preparation_non_regression(sum(row['baseline_ns']), sum(row['candidate_ns'])):
            result.append(row['run'])
    return result


def qualify(controls, ledger):
    order = [row['kind'] for row in controls]
    if order != ['baseline', 'candidate', 'candidate', 'baseline']:
        raise ValueError('complete fixed ABBA control required; no fastest-run selection')
    unresolved = unresolved_failures(ledger)
    phases = {}
    failed = bool(unresolved)
    for phase in ('build', 'prepare', 'prepare-warm'):
        totals = {'baseline': 0, 'candidate': 0}
        complete = True
        accounted = True
        for row in controls:
            receipt = row['phases'][phase]
            n = receipt['wall_nanoseconds']
            if type(n) is not int or n < 0:
                raise ValueError('nonnegative native monotonic nanoseconds required')
            usage = receipt.get('child_usage_delta', {})
            accounted = accounted and all(
                type(usage.get(key)) in (int, float) and math.isfinite(usage[key]) and usage[key] >= 0
                for key in ('ru_utime', 'ru_stime'))
            totals[row['kind']] += n
            complete = complete and receipt['exit_code'] == 0 and not (
                receipt['foreign_compilers'] or receipt['audit_errors'])
        warm = sum(len(row['warm_changed_outputs']) for row in controls if row['kind'] == 'candidate')
        regression = not preparation_non_regression(totals['baseline'], totals['candidate'])
        # This admits only measured phase costs. It makes no compiler/allocator
        # complexity or source-refinement claim. Those need separate work traces.
        admitted = preparation_admitted(totals['baseline'], totals['candidate'], warm,
                                        len(unresolved), True, complete, accounted)
        failed = preparation_latch_failure(failed, regression or not admitted)
        phases[phase] = {**totals, 'regression': regression, 'cost_accounted': accounted,
                         'admitted': admitted}
    return {'schema': 'ascent.preparation-admission.v1', 'phases': phases,
            'unresolved_runs': unresolved, 'admitted': not failed,
            'scope': 'measurement admission only; collector/source refinement remains open'}
