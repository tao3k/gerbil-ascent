# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Historical failures must reject the actual generated CI decision."""
import copy
import json
from pathlib import Path
import unittest

from ascent_workbench.preparation_admission import qualify, unresolved_failures
from ascent_workbench.preparation_policy import (
    preparation_admitted, preparation_latch_failure, preparation_non_regression,
)

ROOT = Path(__file__).resolve().parents[2]
LEDGER = ROOT / 't/qualification/fixtures/preparation/unresolved.json'


class PreparationAdmissionTests(unittest.TestCase):
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
