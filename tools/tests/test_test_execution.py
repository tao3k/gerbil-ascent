"""Exercise cross-process overlap, exclusion, inherited leases and failure exits."""
import importlib.util
import os
import json
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'test_execution.py'
spec = importlib.util.spec_from_file_location('scheduler', SCRIPT)
scheduler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scheduler)


class SchedulingTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.children = []
        self.loader = (
            f'import importlib.util; s=importlib.util.spec_from_file_location("lane", {str(SCRIPT)!r}); '
            f'm=importlib.util.module_from_spec(s); s.loader.exec_module(m); '
            f'm.ROOT=m.Path({str(self.root)!r}); '
            'raise SystemExit(m.main())')

    def tearDown(self):
        for child in self.children:
            if child.poll() is None:
                child.terminate()
            child.communicate(timeout=10)
        self.temporary.cleanup()

    def start(self, options, command):
        child = subprocess.Popen([sys.executable, '-c', self.loader,
                                  'run', *options, '--', *command],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.children.append(child)
        return child

    def wait_file(self, name):
        deadline = time.monotonic() + 5
        while not (self.root / name).exists():
            if time.monotonic() >= deadline:
                self.fail(f'missing fixture signal: {name}')
            time.sleep(0.01)

    def test_semantic_processes_overlap_and_exclusive_waits(self):
        worker = ('from pathlib import Path; import time,sys; '
                  'p=Path(sys.argv[1]); p.write_text("started"); '
                  '\nwhile not Path("release").exists(): time.sleep(.01)')
        options = ['--module', 't/qualification/ascent-strata-test.ss']
        first = self.start(options, [sys.executable, '-c', worker, 'first'])
        second = self.start(options, [sys.executable, '-c', worker, 'second'])
        self.wait_file('first')
        self.wait_file('second')
        exclusive = self.start([], [sys.executable, '-c',
                                     'from pathlib import Path; Path("exclusive").touch()'])
        time.sleep(0.2)
        self.assertFalse((self.root / 'exclusive').exists())
        (self.root / 'release').touch()
        for child in [first, second, exclusive]:
            self.assertEqual(child.wait(timeout=5), 0)
        self.assertTrue((self.root / 'exclusive').exists())

    def test_nested_exclusive_does_not_deadlock(self):
        inner = [sys.executable, '-c', self.loader, 'run', '--', sys.executable,
                 '-c', 'from pathlib import Path; Path("nested").touch()']
        child = self.start([], inner)
        self.assertEqual(child.wait(timeout=5), 0)
        self.assertTrue((self.root / 'nested').exists())

    def test_child_failure_is_preserved(self):
        child = self.start([], [sys.executable, '-c', 'raise SystemExit(7)'])
        self.assertEqual(child.wait(timeout=5), 7)

    def test_unknown_module_is_exclusive(self):
        child = self.start(['--module', 't/qualification/ascent-rule-program-test.ss'],
                           [sys.executable, '-c', 'pass'])
        output, _ = child.communicate(timeout=5)
        self.assertEqual(child.returncode, 0)
        self.assertIn('START exclusive', output)

    def test_parallel_rejects_unadmitted_module_before_start(self):
        result = subprocess.run([sys.executable, '-c', self.loader, 'parallel', '--jobs', '2',
                                 't/qualification/ascent-rule-program-test.ss'],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 1)
        self.assertIn('explicitly admitted', result.stderr)

    def test_parallel_aggregates_worker_failure_and_keeps_log(self):
        executable = self.root / 'just'
        executable.write_text('#!/bin/sh\necho "worker fixture"\nexit 7\n')
        executable.chmod(0o755)
        environment = os.environ.copy()
        environment['PATH'] = str(self.root) + os.pathsep + environment['PATH']
        result = subprocess.run([sys.executable, '-c', self.loader, 'parallel',
                                 '--jobs', '2'], env=environment,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 1)
        logs = list((self.root / '.gerbil/test-execution').glob('parallel-*/*.log'))
        self.assertEqual(len(logs), len(scheduler.PARALLEL_MODULES))
        self.assertTrue(all('worker fixture' in path.read_text() for path in logs))

    def test_suite_runs_every_discovered_module_once_and_retains_failures(self):
        directory = self.root / 't/qualification'
        directory.mkdir(parents=True)
        names = ['ascent-poo-primitives-test.ss', 'ascent-strata-test.ss',
                 'unknown-test.ss', 'ascent-rule-program-test.ss']
        for name in names:
            (directory / name).touch()
        executable = self.root / 'just'
        executable.write_text('#!/bin/sh\necho "$2" >> calls\n'
                              'case "$2" in *unknown*) exit 7;; esac\nexit 0\n')
        executable.chmod(0o755)
        environment = os.environ.copy()
        environment['PATH'] = str(self.root) + os.pathsep + environment['PATH']
        result = subprocess.run([sys.executable, '-c', self.loader, 'suite',
                                 '--jobs', '4'], env=environment,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 1)
        calls = (self.root / 'calls').read_text().splitlines()
        self.assertEqual(sorted(calls), sorted('t/qualification/' + n for n in names))
        self.assertIn('parallel=2 exclusive=2', result.stdout)
        self.assertIn('modules=4 failed=1', result.stdout)

    def test_suite_phase_barrier_and_machine_receipt(self):
        directory = self.root / 't/qualification'
        directory.mkdir(parents=True)
        names = ['ascent-binding-test.ss', 'ascent-set-source-test.ss', 'unknown-test.ss']
        for name in names:
            (directory / name).touch()
        executable = self.root / 'just'
        executable.write_text('#!' + sys.executable + '\n' +
            'from pathlib import Path\nimport sys,time\n'
            'name=Path(sys.argv[2]).name\n'
            'if name == "unknown-test.ss":\n'
            ' assert Path("ascent-binding-test.ss.done").exists()\n'
            ' assert Path("ascent-set-source-test.ss.done").exists()\n'
            'else: time.sleep(.1)\n'
            'Path(name+".done").touch()\n')
        executable.chmod(0o755)
        environment = os.environ.copy()
        environment['PATH'] = str(self.root) + os.pathsep + environment['PATH']
        result = subprocess.run([sys.executable, '-c', self.loader, 'suite', '--jobs', '12'],
                                env=environment, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        receipts = list((self.root / '.gerbil/test-execution').glob('suite-*.json'))
        self.assertEqual(len(receipts), 1)
        summary = json.loads(receipts[0].read_text())
        self.assertFalse(summary['failed'])
        self.assertEqual(summary['configured_jobs'], 12)
        self.assertEqual(sorted(row['module'] for row in summary['results']), summary['requested'])
        self.assertEqual([row['lane'] for row in summary['results']],
                         ['parallel', 'parallel', 'exclusive'])
        self.assertTrue(all(Path(row['log']).exists() for row in summary['results']))

    def test_parallel_cancellation_reaps_term_resistant_worker(self):
        executable = self.root / 'just'
        executable.write_text('#!' + sys.executable + '\n' +
            'import signal,time,os\nfrom pathlib import Path\n'
            'signal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
            'Path("worker-pid").write_text(str(os.getpid()))\n'
            'Path("worker-ready").touch()\n'
            'while True: time.sleep(.05)\n')
        executable.chmod(0o755)
        environment = os.environ.copy()
        environment['PATH'] = str(self.root) + os.pathsep + environment['PATH']
        child = subprocess.Popen([sys.executable, '-c', self.loader, 'parallel', '--jobs', '1',
                                  't/qualification/ascent-strata-test.ss'], env=environment,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.children.append(child)
        self.wait_file('worker-ready')
        began = time.monotonic()
        child.terminate()
        self.assertEqual(child.wait(timeout=8), 130)
        self.assertLess(time.monotonic()-began, 8)
        with self.assertRaises(ProcessLookupError):
            os.kill(int((self.root / 'worker-pid').read_text()), 0)
        receipts = list((self.root / '.gerbil/test-execution').glob('parallel-*/summary.json'))
        self.assertEqual(len(receipts), 1)
        self.assertTrue(json.loads(receipts[0].read_text())['cancelled'])

    def test_native_receipt_errors_are_rejected_even_on_zero_exit(self):
        shutil.copyfile(SCRIPT.parent.parent / 'justfile', self.root / 'justfile')
        tools = self.root / 'tools'
        tools.mkdir()
        for name in ['test_execution.py', 'assert-test-cases.awk']:
            shutil.copyfile(SCRIPT.parent / name, tools / name)
        module = 't/qualification/ascent-strata-test.ss'
        (self.root / module).parent.mkdir(parents=True)
        (self.root / module).touch()
        executable = self.root / 'gerbil'
        executable.write_text('#!' + sys.executable + '\n' +
            'import os\nmode=os.environ["FIXTURE_MODE"]\n'
            f'module={module!r}\n'
            'print("MODULE "+module)\n'
            'if mode != "empty": print("CASE fixture\\nCASE-OK fixture")\n'
            'if mode == "error": print("ERROR MODULE fixture")\n'
            'print("MODULE-OK "+module+(".extra" if mode == "wrong" else ""))\n'
            'print("HARNESS-OK fixture\\nOK")\n')
        executable.chmod(0o755)
        environment = os.environ.copy()
        environment['PATH'] = str(self.root) + os.pathsep + environment['PATH']
        environment.pop('ASCENT_TEST_EXCLUSIVE_FD', None)
        for mode, expected in [('good', 0), ('error', 1), ('empty', 1), ('wrong', 1)]:
            with self.subTest(mode=mode):
                environment['FIXTURE_MODE'] = mode
                result = subprocess.run(['just', 'test-file', module], cwd=self.root,
                                        env=environment, capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, expected, result.stdout+result.stderr)

    def test_explicit_jobs_above_four_are_not_capped(self):
        executable = self.root / 'just'
        executable.write_text('#!/bin/sh\nexit 0\n')
        executable.chmod(0o755)
        environment = os.environ.copy()
        environment['PATH'] = str(self.root) + os.pathsep + environment['PATH']
        result = subprocess.run([sys.executable, '-c', self.loader, 'parallel',
                                 '--jobs', '12'], env=environment,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertIn(f'configured-jobs=12 workers=12 modules={len(scheduler.PARALLEL_MODULES)}', result.stdout)

    def test_native_capacity_projection_is_used_for_default(self):
        # Check the Python boundary, not a second implementation of native parsing.
        code = self.loader.split('raise SystemExit(m.main())')[0] + (
            'from unittest.mock import patch; '
            '\nwith patch.object(m.subprocess, "check_output", return_value="12\\n") as call:\n'
            ' assert m.resolve_jobs(None) == 12\n'
            ' assert call.call_args.args[0][0] == "gxi"\n'
            ' assert m.resolve_jobs("2") == 2\n'
            ' assert call.call_count == 1\n')
        result = subprocess.run([sys.executable, '-c', code], capture_output=True,
                                text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_termination_releases_lease(self):
        child = self.start([], [sys.executable, '-c',
                                'from pathlib import Path; import time; '
                                'Path("running").touch(); time.sleep(60)'])
        self.wait_file('running')
        child.terminate()
        self.assertEqual(child.wait(timeout=5), 130)
        next_child = self.start([], [sys.executable, '-c', 'pass'])
        self.assertEqual(next_child.wait(timeout=5), 0)


if __name__ == '__main__':
    unittest.main()
