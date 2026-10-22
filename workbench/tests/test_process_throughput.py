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


class SameRequestCostEvidence(unittest.TestCase):
    def observations(self):
        common = dict(mode="rayon", vms="1", rust_threads="12", clients="12")
        return ({**common, "task": "7", "total_ns": "100", "replace_ns": "60",
                 "run_export_ns": "25", "validation_ns": "15"},
                {**common, "max_ns": "100", "completed_requests": "12", "slowest_schema": "same-request-v1"})

    def test_original_total_and_all_checked_phases_stay_visible(self):
        trace, soak = self.observations()
        result = CONTROL.longest_request([trace], [soak])
        self.assertEqual(result, dict(task=7, total_ns=100, replace_ns=60,
                                     run_export_ns=25, validation_ns=15))

    def test_cross_request_maxima_missing_and_foreign_evidence_are_rejected(self):
        trace, soak = self.observations()
        for traces, soaks in [([], [soak]), ([trace, trace], [soak]),
                              ([{**trace, "task": "12"}], [soak]),
                              ([{**trace, "replace_ns": "90"}], [soak]),
                              ([{**trace, "total_ns": "110", "validation_ns": "25"}], [soak]),
                              ([{**trace, "clients": "1"}], [soak]),
                              ([{**trace, "validation_ns": "-1"}], [soak])]:
            with self.subTest(traces=traces), self.assertRaises(ValueError):
                CONTROL.longest_request(traces, soaks)

    def test_soak_identity_excludes_fixed_sample_tasks(self):
        trace, soak = self.observations()
        for task in (131, 144):
            with self.subTest(task=task), self.assertRaises(ValueError):
                CONTROL.longest_request([{**trace, "task": str(task)}], [soak], 132)
        self.assertEqual(CONTROL.longest_request([{**trace, "task": "139"}], [soak], 132)["task"], 139)

    def test_historical_absence_is_not_reconstructed_as_phase_evidence(self):
        self.assertIsNone(CONTROL.longest_request([], [{"max_ns": "100"}]))
