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


class DiagnosticAdmission(unittest.TestCase):
    def complete_evidence(self):
        common = dict(mode='vm', vms='1', rust_threads='1', clients='12')
        def line(tag, **values):
            return tag + ' ' + ' '.join(f'{key}={value}' for key, value in values.items()) + '\n'
        stderr = line('PROCESS-OWNER', pid=123, processors=1, domain=1)
        stderr += line('PROCESS-READY', **common, checkpoint_transport='buffered-socket', work_distribution='adaptive')
        for sample in range(5):
            stderr += line('PROCESS-SAMPLE', **common, sample=sample, tasks=12, throughput_per_s=1,
                           p50_ns=10, p95_ns=10, max_overlapping_vm_calls=1,
                           native_calls=24, checkpoints=1, shared_checkpoints=0, answer_sha='a'*64)
        stderr += line('PROCESS-SOAK', **common, requested_ns=30_000_000_000, wall_ns=30_000_000_001,
                       completed_requests=12, checked_requests=12, minimum_client_requests=1,
                       histogram_resolution_ns=100_000, histogram_buckets=65_536,
                       p50_lower_ns=0, p50_upper_ns=100_000, p95_lower_ns=0, p95_upper_ns=100_000,
                       max_ns=100, checkpoints=1, shared_checkpoints=0, slowest_schema='same-request-v1')
        stderr += line('PROCESS-SLOWEST', **common, task=72, total_ns=100,
                       replace_ns=60, run_export_ns=25, validation_ns=15)
        stdout = HEADER + ''.join(request(sample, sample*12+task) for sample in range(5) for task in range(12))
        return stdout, stderr

    def test_trace_cannot_be_admitted_even_with_complete_structural_evidence(self):
        import argparse
        import tempfile
        from unittest.mock import patch
        from types import SimpleNamespace
        for diagnostic in [False, True]:
            with self.subTest(diagnostic=diagnostic), tempfile.TemporaryDirectory() as directory:
                args = argparse.Namespace(benchmark=Path('/not-run/benchmark'), worker=Path('/not-run/worker'), output=Path(directory))
                process = SimpleNamespace(pid=123, returncode=0, communicate=lambda **_: self.complete_evidence())
                with patch.dict(CONTROL.os.environ, {}, clear=True), patch.object(CONTROL, 'compilers', return_value=[]), patch.object(CONTROL, 'process_snapshot', return_value=[dict(pid=123,ppid=0,rss_kib=1024,command='benchmark')]), patch.object(CONTROL, 'thread_population', return_value={123:12}), patch.object(CONTROL, 'cpu_resources', return_value={'maximum_process_rss_bytes': 1024}), \
                        patch.object(CONTROL.subprocess, 'Popen', return_value=process) as launch:
                    row = CONTROL.run_case(args, ('small', 12, 4, 8), ('vm', 1, 1), 'adaptive', diagnostic=diagnostic)
                self.assertEqual(row['valid'], not diagnostic)
                self.assertEqual(row['diagnostic_only'], diagnostic)
                self.assertEqual('ASCENT_PROCESS_TRACE' in launch.call_args.kwargs['env'], diagnostic)

    def test_zombie_group_cleanup_preserves_timeout_and_every_observation(self):
        import argparse
        import subprocess
        import tempfile
        from unittest.mock import Mock, patch
        from types import SimpleNamespace
        from ascent_workbench.supervision import signal_group
        with tempfile.TemporaryDirectory() as directory:
            args = argparse.Namespace(benchmark=Path('/not-run/benchmark'), worker=Path('/not-run/worker'), output=Path(directory))
            process = SimpleNamespace(pid=123, returncode=-15, communicate=Mock(side_effect=[
                subprocess.TimeoutExpired('benchmark', 240),
                subprocess.TimeoutExpired('benchmark', 2), self.complete_evidence()]))
            with patch.dict(CONTROL.os.environ, {}, clear=True), patch('sys.platform', 'darwin'), \
                    patch.object(CONTROL, 'compilers', return_value=[]), \
                    patch.object(CONTROL, 'process_snapshot', return_value=[]), \
                    patch.object(CONTROL, 'thread_population', return_value={}), \
                    patch.object(CONTROL, 'cpu_resources', return_value={'maximum_process_rss_bytes': 1024}), \
                    patch.object(CONTROL.subprocess, 'Popen', return_value=process), \
                    patch.object(CONTROL, 'signal_group', wraps=signal_group), \
                    patch('os.killpg', side_effect=[None, PermissionError(1, 'zombie only')]), \
                    patch('ascent_workbench.supervision.subprocess.run', return_value=subprocess.CompletedProcess([], 0, stdout='123 Z\n')):
                row = CONTROL.run_case(args, ('small', 12, 4, 8), ('vm', 1, 1), 'adaptive')
            self.assertEqual(row['status'], 'timeout')
            self.assertFalse(row['valid'])
            self.assertEqual(len(row['samples']), 5)
            self.assertTrue((Path(directory) / (row['key'] + '.stderr')).exists())
            self.assertEqual([call.kwargs['timeout'] for call in process.communicate.call_args_list], [240, 2, 5])

    def test_successful_diagnostic_does_not_promote_or_repeat_original_failure(self):
        import argparse
        import copy
        import json
        import tempfile
        from unittest.mock import patch
        original = dict(key='failed-vm', workload='parallel-closure', mode='vm', vms=1,
                        rust_threads=1, tasks=24, groups=256, width=16, valid=False, status=101)
        rows = [original, {**original, 'mode': 'rayon'}, {**original, 'status': 0},
                {**original, 'diagnostic_only': True}]
        before = copy.deepcopy(rows)
        with tempfile.TemporaryDirectory() as directory:
            args = argparse.Namespace(benchmark=Path('/not-run/benchmark'), worker=Path('/not-run/worker'), output=Path(directory))
            with patch.object(CONTROL, 'run_case', return_value={'valid': True, 'status': 0}) as reproduce:
                CONTROL.diagnose_failed_vm_cases(args, rows, 'adaptive')
            self.assertEqual(reproduce.call_count, 1)
            self.assertTrue(reproduce.call_args.kwargs['diagnostic'])
            receipt = json.loads((Path(directory) / 'diagnostics/result.json').read_text())
            self.assertFalse(receipt['admitted'])
            self.assertEqual(receipt['runs'][0]['original_status'], 101)
        self.assertEqual(rows, before)


class RuntimeIdentityAndResources(unittest.TestCase):
    def test_instances_share_one_pid_but_require_distinct_domains(self):
        owners = [dict(pid="8", domain=str(i+1), processors="1") for i in range(12)]
        self.assertTrue(CONTROL.owner_identities_valid(owners, "instances", 12))
        self.assertFalse(CONTROL.owner_identities_valid(owners, "vm", 12))
        self.assertFalse(CONTROL.owner_identities_valid(owners[:-1] + [owners[0]], "instances", 12))
        self.assertFalse(CONTROL.owner_identities_valid([{**owners[0], "processors": "2"}], "instances", 1))

    def test_process_tree_does_not_charge_other_tasks_and_keeps_shared_rss_caveat(self):
        snapshot = [dict(pid=1, ppid=0, rss_kib=10), dict(pid=2, ppid=1, rss_kib=20),
                    dict(pid=3, ppid=2, rss_kib=30), dict(pid=4, ppid=0, rss_kib=900)]
        self.assertEqual(CONTROL.process_tree_resources(snapshot, 1),
                         dict(pids=[1,2,3], processes=3, rss_sum_kib=60, maximum_process_rss_kib=30))

    def test_missing_cpu_accounting_is_not_reported_as_zero_cost(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "resource"
            path.write_text("0.2 real 0.3 user 0.1 sys\n2048 maximum resident set size\n")
            self.assertEqual(CONTROL.cpu_resources(path)["average_cpu_cores"], 2)
            path.write_text("time: failed\n")
            with self.assertRaises(ValueError):
                CONTROL.cpu_resources(path)


class ThreadResourceEvidence(unittest.TestCase):
    def test_darwin_blank_user_rows_count_real_threads_and_exclude_other_processes(self):
        output = "USER       PID   TT   %CPU STAT\ngu nt    70687   ??    0.0 S\n         70687         0.0 S\n         70687         0.0 S\nother    99999   ??    0.0 S\n"
        self.assertEqual(CONTROL.parse_thread_counts(output, {70687}, True), {70687:3})

    def test_linux_counts_threads_without_charging_foreign_pids(self):
        self.assertEqual(CONTROL.parse_thread_counts("12\n12\n13\n14\n", {12,13}, False), {12:2,13:1})

class OwnerConfigurationEvidence(unittest.TestCase):
    def test_vm_processor_population_and_rust_coordinator_count_are_independent(self):
        expected = [(mode, owners, 12) for mode in ('vm', 'instances') for owners in (1, 3, 12)]
        expected += [('rayon', 1, threads) for threads in (1, 3, 6, 8, 12)]
        self.assertEqual(CONTROL.configurations(True), expected)
        self.assertEqual(CONTROL.configurations(False), [row for row in expected if row[0] != 'instances'])

class JoinedOwnerEvidence(unittest.TestCase):
    def test_pending_roots_missing_and_duplicate_receipts_never_qualify_native_teardown(self):
        receipt = 'OWNER-SHUTDOWN mode=instances joined=12 pending=0 panicked=0 roots=0\n'
        self.assertTrue(CONTROL.owner_shutdown_valid(receipt, 'instances', 12))
        for rejected in ['', receipt + receipt, receipt.replace('pending=0', 'pending=1'), receipt.replace('roots=0', 'roots=1'), receipt.replace('joined=12', 'joined=11'), receipt.replace('panicked=0', 'panicked=1')]:
            self.assertFalse(CONTROL.owner_shutdown_valid(rejected, 'instances', 12))
