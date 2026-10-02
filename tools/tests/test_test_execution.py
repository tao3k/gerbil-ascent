"""Exercise cross-process overlap, exclusion, inherited leases and failure exits."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'test_execution.py'


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
        self.assertEqual(len(logs), 7)
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
        self.assertIn('configured-jobs=12 workers=7 modules=7', result.stdout)

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
