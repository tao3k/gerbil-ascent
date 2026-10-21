"""Production throughput receipts require complete, unique request evidence."""
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location(
    'process_throughput', Path(__file__).resolve().parents[2] / 'tools/ci/process-throughput.py')
CONTROL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTROL)
HEADER = 'sample\ttask\tlatency_ns\tcompletion_ns\treplace_ns\trun_export_ns\tanswer_sha\n'


def request(sample, task, latency=10, replace=2, run_export=7):
    return f'{sample}\t{task}\t{latency}\t20\t{replace}\t{run_export}\t' + 'a' * 64 + '\n'


class ProductionThroughputEvidence(unittest.TestCase):
    def test_complete_fixed_work_has_separate_source_and_execution_costs(self):
        result = CONTROL.request_phases(HEADER + request(0, 0) + request(1, 1), 1, 2)
        self.assertEqual(result['checked_fixed_work_requests'], 2)
        self.assertEqual(result['median_replace_ms'], 0.000002)
        self.assertEqual(result['median_run_export_ms'], 0.000007)

    def test_missing_and_repeated_requests_cannot_be_admitted(self):
        for evidence in (HEADER + request(0, 0),
                         HEADER + request(0, 0) * 2):
            with self.subTest(evidence=evidence), self.assertRaises(ValueError):
                CONTROL.request_phases(evidence, 1, 2)

    def test_cross_sample_identity_and_impossible_phase_costs_are_rejected(self):
        for evidence in (request(1, 0), request(0, 0, replace=-1),
                         request(0, 0, latency=8), request(0, 0).replace('aaaa', 'zzzz')):
            with self.subTest(evidence=evidence), self.assertRaises(ValueError):
                CONTROL.request_phases(HEADER + evidence, 1, 1)
