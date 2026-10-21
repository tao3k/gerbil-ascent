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


# This is a bounded source transformation for private frozen test carriers,
# not permission to edit production/workload algorithms in a compiler study.
def shared_reference_paths(changed, before, after):
    import hashlib
    canonical = 't/performance/uf-dense/'
    bodies = {
        'reference-initialization': 'c7f86dcef7295fe4f198eaad0b7b66f62ad4658f359d1457a89a4a755e95713e',
        'reference-view-replay': '3ff78c5d8f9fc322ba279652eda0b233256d3a1d63c44411249247102f3a2893',
    }
    deleted = {}
    edits = {}
    for lane in ('axis', 'growth', 'reuse'):
        old = f't/performance/uf-{lane}/reference-initialization'
        deleted[old + '.ss'] = 'reference-initialization'
        edits[f't/performance/uf-{lane}/build.ss'] = (old, canonical + 'reference-initialization')
        edits[f't/performance/uf-{lane}/reference-evaluate.ss'] = (
            '"reference-initialization.ss"', ':gerbil-ascent/' + canonical + 'reference-initialization')
    old = 't/performance/uf-materialization/reference-view-replay'
    deleted[old + '.ss'] = 'reference-view-replay'
    for name in ('t/performance/uf-materialization/build.ss',
                 't/performance/uf-materialization/fixture.ss',
                 't/qualification/ascent-uf-materialization-test.ss'):
        edits[name] = (old, canonical + 'reference-view-replay')
    edits['t/performance/uf-materialization/reference-view-state.ss'] = (
        '"reference-view-replay.ss"', ':gerbil-ascent/' + canonical + 'reference-view-replay')
    paths = set(deleted) | set(edits)
    if not paths.intersection(changed):
        return set()
    if not paths.issubset(changed):
        raise ValueError('incomplete frozen reference carrier rewrite')
    for name, kind in deleted.items():
        body = before(name)
        if (body is None or hashlib.sha256(body).hexdigest() != bodies[kind]
                or before(canonical + kind + '.ss') != body
                or after(canonical + kind + '.ss') != body or after(name) is not None):
            raise ValueError('frozen reference body or deletion differs: ' + name)
    for name, (old, new) in edits.items():
        body = before(name)
        needle, replacement = old.encode(), new.encode()
        if body is None or body.count(needle) != 1 or after(name) != body.replace(needle, replacement):
            raise ValueError('frozen reference import rewrite differs: ' + name)
    return paths


def development_dependency_paths(changed, before, after):
    """Admit only removal of the ASP production edge in this build-cost study.

    Tool entrypoints are outside the measured production/workload source set.
    This does not admit changes to any other production dependency or a change
    to the ASP implementation; the upstream one-manifest-only diff is recorded
    separately with the SDK and dependency seed identities.
    """
    manifest = 'gerbil.pkg'
    paths = {'dev/gerbil.pkg', 'dev/build.ss', 'dev/production-build-test.ss'}
    if manifest not in changed:
        return set()
    edge = b'\n  "github.com/tao3k/asp-gerbil-scheme@f5b7c009d2cab61144a8af18008a0bfba3056584"'
    original = before(manifest)
    tools = after('dev/gerbil.pkg')
    if (original is None or original.count(edge) != 1
            or after(manifest) != original.replace(edge, b'')
            or not paths.issubset(changed)
            or any(before(path) is not None or after(path) is None for path in paths)
            or tools is None
            or b'github.com/tao3k/asp-gerbil-scheme@31c7ddee27d775a6164cbe8f032c6405cc7b353d' not in tools):
        raise ValueError('development dependency split differs from the bound transformation')
    return paths | {manifest}
