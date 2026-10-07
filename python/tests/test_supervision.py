# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Check build supervision against CPU work, a sleeping child and failure."""
from pathlib import Path
import subprocess
import sys
import unittest


class BuildActivity(unittest.TestCase):
    def run_child(self, code):
        return subprocess.run(
            [sys.executable, str(Path(__file__).parents[1] / 'src/ascent_test_support/supervision.py'),
             '--cpu-progress', '--startup-seconds', '2', '--idle-seconds', '2',
             '--', sys.executable, '-c', code],
            capture_output=True, text=True, timeout=15)

    def test_cpu_work_can_continue_without_output(self):
        result = self.run_child('import time\nend=time.monotonic()+4\n'
                                'while time.monotonic()<end: pass\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('cpu-advance=', result.stderr)

    def test_sleeping_child_is_stopped(self):
        result = self.run_child('import time; time.sleep(10)')
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertIn('FAIL', result.stderr)

    def test_child_failure_propagates(self):
        result = self.run_child('raise SystemExit(7)')
        self.assertEqual(result.returncode, 7, result.stderr)


class SeparateStreams(unittest.TestCase):
    def run_child(self, code):
        return subprocess.run(
            [sys.executable, str(Path(__file__).parents[1] / 'src/ascent_test_support/supervision.py'),
             '--separate-stderr', '--startup-seconds', '.5', '--idle-seconds', '.5',
             '--', sys.executable, '-c', code],
            capture_output=True, timeout=5)

    def test_binary_stdout_and_diagnostics_remain_separate(self):
        result = self.run_child("import sys; sys.stdout.buffer.write(b'row\\x00\\xff\\n'); "
                                "sys.stderr.buffer.write(b'admitted\\n')")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b'row\x00\xff\n')
        self.assertEqual(result.stderr, b'admitted\n')

    def test_real_stderr_progress_keeps_empty_stdout_alive(self):
        result = self.run_child("import sys,time\nfor i in range(6):\n"
                                " print(i,file=sys.stderr,flush=True); time.sleep(.2)\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b'')
        self.assertEqual(result.stderr, b'0\n1\n2\n3\n4\n5\n')

    def test_stalled_child_is_rejected_and_failure_propagates(self):
        stalled = self.run_child('import time; time.sleep(2)')
        self.assertEqual(stalled.returncode, 124, stalled.stderr)
        self.assertEqual(stalled.stdout, b'')
        self.assertIn(b'FAIL', stalled.stderr)
        failed = self.run_child('raise SystemExit(7)')
        self.assertEqual(failed.returncode, 7, failed.stderr)


if __name__ == '__main__':
    unittest.main()
