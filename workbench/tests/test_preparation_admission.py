# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Historical failures must reject the actual generated CI decision."""
import copy
import json
from pathlib import Path
import unittest

from ascent_workbench.preparation_admission import qualify, unresolved_failures, shared_reference_paths, development_dependency_paths
from ascent_workbench.preparation_policy import (
    preparation_admitted, preparation_latch_failure, preparation_non_regression,
)

ROOT = Path(__file__).resolve().parents[2]
LEDGER = ROOT / 't/qualification/fixtures/preparation/unresolved.json'


class PreparationAdmissionTests(unittest.TestCase):
    def test_dev_split_cannot_change_other_production_dependencies(self):
        edge = b'\n  "github.com/tao3k/asp-gerbil-scheme@0f78289a7ae465a84370f5d94d8d14671f3c43af"'
        original = b'(package: gerbil-ascent depend: ("core@fixed"' + edge + b'))\n'
        before = {'gerbil.pkg': original}
        after = {'gerbil.pkg': original.replace(edge, b'')}
        for name in ('gerbil.pkg', 'build.ss', 'production-build-test.ss'):
            after['dev/' + name] = (ROOT / 'dev' / name).read_bytes()
        changed = set(after)
        self.assertEqual(development_dependency_paths(changed, before.get, after.get), changed)
        for replacement in (after['gerbil.pkg'].replace(b'core@fixed', b'core@other'),
                            original, after['gerbil.pkg'] + b'; extra change'):
            bad = dict(after, **{'gerbil.pkg': replacement})
            with self.assertRaises(ValueError):
                development_dependency_paths(changed, before.get, bad.get)
        for missing in ('dev/gerbil.pkg', 'dev/build.ss', 'dev/production-build-test.ss'):
            with self.assertRaises(ValueError):
                development_dependency_paths(changed - {missing}, before.get, after.get)
        bad = dict(after, **{'dev/gerbil.pkg': b'(depend: ("asp@other"))'})
        with self.assertRaises(ValueError):
            development_dependency_paths(changed, before.get, bad.get)

    def test_shared_carriers_require_frozen_bodies_deletions_and_exact_import_edits(self):
        baseline, candidate = {}, {}
        canonical = 't/performance/uf-dense/'
        edits = {}
        for lane in ('axis', 'growth', 'reuse'):
            old = f't/performance/uf-{lane}/reference-initialization'
            body = (ROOT / (canonical + 'reference-initialization.ss')).read_bytes()
            baseline[old + '.ss'] = body
            baseline[canonical + 'reference-initialization.ss'] = body
            candidate[canonical + 'reference-initialization.ss'] = body
            edits[f't/performance/uf-{lane}/build.ss'] = (old, canonical + 'reference-initialization')
            edits[f't/performance/uf-{lane}/reference-evaluate.ss'] = (
                '"reference-initialization.ss"', ':gerbil-ascent/' + canonical + 'reference-initialization')
        old = 't/performance/uf-materialization/reference-view-replay'
        body = (ROOT / (canonical + 'reference-view-replay.ss')).read_bytes()
        baseline[old + '.ss'] = body
        baseline[canonical + 'reference-view-replay.ss'] = body
        candidate[canonical + 'reference-view-replay.ss'] = body
        for name in ('t/performance/uf-materialization/build.ss',
                     't/performance/uf-materialization/fixture.ss',
                     't/qualification/ascent-uf-materialization-test.ss'):
            edits[name] = (old, canonical + 'reference-view-replay')
        edits['t/performance/uf-materialization/reference-view-state.ss'] = (
            '"reference-view-replay.ss"', ':gerbil-ascent/' + canonical + 'reference-view-replay')
        for name, (old, new) in edits.items():
            candidate[name] = (ROOT / name).read_bytes()
            self.assertEqual(candidate[name].count(new.encode()), 1)
            baseline[name] = candidate[name].replace(new.encode(), old.encode())
        changed = (set(baseline) | set(candidate)) - {canonical + 'reference-initialization.ss',
                                                    canonical + 'reference-view-replay.ss'}
        self.assertEqual(len(changed), 14)
        self.assertEqual(shared_reference_paths(changed, baseline.get, candidate.get), changed)
        for name in changed:
            bad = dict(candidate)
            bad[name] = (candidate.get(name) or baseline[name]) + b'\n(extra-edit)\n'
            with self.subTest(path=name), self.assertRaises(ValueError):
                shared_reference_paths(changed, baseline.get, bad.get)
            with self.assertRaises(ValueError):
                shared_reference_paths(changed - {name}, baseline.get, candidate.get)
        for name in [canonical + 'reference-initialization.ss', canonical + 'reference-view-replay.ss']:
            bad = dict(candidate, **{name: candidate[name] + b'\n'})
            with self.assertRaises(ValueError):
                shared_reference_paths(changed, baseline.get, bad.get)
        unknown = 'program/evaluate.ss'
        self.assertNotIn(unknown, shared_reference_paths(changed | {unknown}, baseline.get, candidate.get))
        self.assertEqual(shared_reference_paths({unknown}, baseline.get, candidate.get), set())

    def test_historical_40_percent_and_five_percent_regressions_reject(self):
        ledger = json.loads(LEDGER.read_text())
        self.assertEqual(unresolved_failures(ledger), [39084120171, 39088480174])
        for row in ledger['records']:
            self.assertFalse(preparation_admitted(sum(row['baseline_ns']),
                sum(row['candidate_ns']), 0, 0, True, True, True))

    def test_later_faster_does_not_clear_prior_failure(self):
        self.assertTrue(preparation_latch_failure(True, False))
        self.assertFalse(preparation_admitted(100, 1, 0, 1, True, True, True))
        self.assertTrue(preparation_non_regression(100, 1))

    def test_all_guards_are_independent(self):
        accepted = [100, 100, 0, 0, True, True, True]
        self.assertTrue(preparation_admitted(*accepted))
        for index, value in ((1, 101), (2, 1), (3, 1), (4, False), (5, False), (6, False)):
            args = accepted.copy()
            args[index] = value
            self.assertFalse(preparation_admitted(*args), (index, value))

    def test_complete_abba_requires_observed_phase_costs(self):
        controls = []
        for kind in ['baseline', 'candidate', 'candidate', 'baseline']:
            controls.append({'kind': kind, 'warm_changed_outputs': [], 'phases': {
                name: {'wall_nanoseconds': 100 if kind == 'baseline' else 1,
                       'exit_code': 0, 'foreign_compilers': [], 'audit_errors': []}
                for name in ('build', 'prepare', 'prepare-warm')}})
        empty = {'schema': 'ascent.preparation-regressions.v1', 'records': []}
        result = qualify(controls, empty)
        self.assertFalse(result['admitted'])
        self.assertFalse(result['phases']['prepare-warm']['admitted'])
        self.assertFalse(result['phases']['prepare']['cost_accounted'])
        observed = copy.deepcopy(controls)
        for row in observed:
            for receipt in row['phases'].values():
                receipt['child_usage_delta'] = {'ru_utime': 1.0, 'ru_stime': 0.0}
        self.assertTrue(qualify(observed, empty)['admitted'])
        replay = qualify(observed, json.loads(LEDGER.read_text()))
        self.assertFalse(replay['admitted'])
        self.assertEqual(replay['unresolved_runs'], [39084120171, 39088480174])
        self.assertTrue(all(not phase['regression'] for phase in replay['phases'].values()))
        observed[1]['phases']['prepare']['child_usage_delta']['ru_utime'] = float('nan')
        self.assertFalse(qualify(observed, empty)['admitted'])
        with self.assertRaises(ValueError):
            qualify(controls[:2], empty)
        invalid = copy.deepcopy(controls)
        invalid[1]['phases']['prepare']['wall_nanoseconds'] = -1
        with self.assertRaises(ValueError):
            qualify(invalid, empty)

    def test_editing_resolution_is_not_a_certificate(self):
        ledger = json.loads(LEDGER.read_text())
        ledger['records'][0]['resolution'] = {'later_run_passed': True}
        with self.assertRaises(ValueError):
            unresolved_failures(ledger)
