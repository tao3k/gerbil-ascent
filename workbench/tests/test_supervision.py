# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Check build supervision against CPU work, a sleeping child and failure."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from ascent_workbench.supervision import cpu_advance, darwin_process_cpu, group_cpu, proc_group_cpu, signal_group


class BuildActivity(unittest.TestCase):
    def run_child(self, code):
        return subprocess.run(
            [sys.executable, str(Path(__file__).parents[1] / 'src/ascent_workbench/supervision.py'),
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

    def test_short_lived_compiler_children_count_after_reaping(self):
        result = self.run_child(
            'import subprocess,sys,time\nend=time.monotonic()+4\n'
            'while time.monotonic()<end:\n'
            ' subprocess.run([sys.executable,"-c",'
            '"import time; end=time.process_time()+.04\\nwhile time.process_time()<end: pass"], check=True)\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('cpu-advance=', result.stderr)

    @unittest.skipUnless(sys.platform == 'darwin', 'Darwin exec CPU counter reset')
    def test_exec_counter_reset_does_not_hide_continuing_native_work(self):
        # Exercise real fork/exec counter reset for two observable intervals.
        # Six CPU seconds cannot promise completion within fifteen wall seconds
        # under contention; the watchdog checks progress, not reserved CPU share.
        work = 'import time\nend=time.monotonic()+3\nwhile time.monotonic()<end: pass\n'
        code = ('import os,sys,time\npid=os.fork()\n'
                'if pid==0:\n'
                ' end=time.monotonic()+3\n'
                ' while time.monotonic()<end: pass\n'
                ' os._exit(0)\n'
                'os.waitpid(pid,0)\n'
                f'os.execv(sys.executable,[sys.executable,"-c",{work!r}])\n')
        result = self.run_child(code)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('basis=own', result.stderr)

    def test_closed_output_does_not_disable_stall_detection(self):
        result = self.run_child('import os,time; os.close(1); os.close(2); time.sleep(10)')
        self.assertEqual(result.returncode, 124, result.stderr)

    def test_closed_output_keeps_real_cpu_work_alive(self):
        result = self.run_child('import os,time\nos.close(1); os.close(2)\n'
                                'end=time.monotonic()+4\nwhile time.monotonic()<end: pass\n')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_failed_leader_does_not_wait_for_orphan_pipe_owners(self):
        result = self.run_child('import subprocess,sys; '
                                'subprocess.Popen([sys.executable,"-c","import time; time.sleep(30)"]); '
                                'raise SystemExit(7)')
        self.assertEqual(result.returncode, 7, result.stderr)

    def test_darwin_cpu_converts_self_and_reaped_child_ticks(self):
        def read(pid, flavor, pointer):
            self.assertEqual((pid, flavor), (42, 1))
            usage = pointer._obj
            usage.user, usage.system = 2400000, 4800000
            usage.child_user, usage.child_system = 7200000, 9600000
            return 0
        for scale in (125 / 3 / 1e9, 1 / 1e9):
            with self.subTest(scale=scale), \
                 patch('ascent_workbench.supervision.darwin_rusage', return_value=read), \
                 patch('ascent_workbench.supervision.darwin_cpu_seconds_per_tick', return_value=scale):
                self.assertAlmostEqual(darwin_process_cpu(42), 24000000 * scale)
                self.assertAlmostEqual(darwin_process_cpu(42, include_children=False), 7200000 * scale)

    @unittest.skipUnless(sys.platform == 'darwin', 'Darwin native CPU clock')
    def test_darwin_native_cpu_matches_process_clock(self):
        before = darwin_process_cpu(os.getpid())
        started = time.process_time()
        while time.process_time() - started < .2:
            pass
        elapsed = time.process_time() - started
        measured = darwin_process_cpu(os.getpid()) - before
        self.assertAlmostEqual(measured, elapsed, delta=.02)

    @unittest.skipUnless(sys.platform == 'darwin', 'Darwin native process groups')
    def test_darwin_sampling_reads_only_the_requested_group_without_ps(self):
        with subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(3)'],
                              start_new_session=True) as child:
            try:
                with patch('ascent_workbench.supervision.subprocess.check_output',
                           side_effect=AssertionError('CPU sampling must not spawn ps')):
                    sample = group_cpu(child.pid)
                self.assertIn(child.pid, sample)
                self.assertNotIn(os.getpid(), sample)
                self.assertGreaterEqual(sample[child.pid], 0)
            finally:
                child.terminate()

    def test_linux_cpu_includes_reaped_children_and_tick_precision(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for pid, group, times in ((11, 42, (2, 3, 4, 5)), (12, 43, (9, 9, 9, 9))):
                process = root / str(pid)
                process.mkdir()
                fields = ['S', '1', str(group)] + ['0'] * 8 + list(map(str, times))
                (process / 'stat').write_text(f'{pid} (compiler (child)) ' + ' '.join(fields))
            (root / '13').mkdir()  # Directory of an already exited compiler.
            self.assertEqual(proc_group_cpu(root, 42, 100), {11: .14})
            self.assertEqual(proc_group_cpu(root, 42, 100, include_children=False), {11: .05})


class CpuSnapshots(unittest.TestCase):
    def test_exec_reset_itself_is_not_progress(self):
        advance, peak = cpu_advance({42: 8}, {42: 0}, 0, 8)
        self.assertEqual((advance, peak), (0, 8))
        # The next real CPU increment must not repay the vanished epoch first.
        self.assertEqual(cpu_advance({42: 0}, {42: .5}, .5, peak), (.5, 8))

    def test_reaping_or_missing_member_alone_never_creates_own_progress(self):
        previous = {42: 1, 43: 7}
        self.assertEqual(cpu_advance(previous, {42: 1}, 1, 8), (0, 8))
        # Reaped CPU becomes inherited CPU, not the parent's own work.
        self.assertEqual(cpu_advance({42: 1}, {42: 1}, 8, 8), (0, 8))
        self.assertEqual(cpu_advance({42: 1}, {42: 1}, 8, 12), (0, 12))

    def test_surviving_worker_progress_is_not_hidden_by_group_snapshot_debt(self):
        self.assertEqual(cpu_advance({42: 1, 43: 7}, {42: 1.5}, 1.5, 12), (.5, 12))
        self.assertEqual(cpu_advance({42: 1}, {42: 1.5}, 13, 12), (1, 13))

    def test_new_pid_first_observation_is_not_own_cpu_progress(self):
        self.assertEqual(cpu_advance({42: 8}, {43: .5}, .5, 8), (0, 8))


class SeparateStreams(unittest.TestCase):
    def run_child(self, code):
        return subprocess.run(
            [sys.executable, str(Path(__file__).parents[1] / 'src/ascent_workbench/supervision.py'),
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

    def test_total_wall_time_does_not_replace_real_inactivity(self):
        advancing = self.run_child("import time\nfor i in range(6):\n"
                                   " print(i, flush=True); time.sleep(.2)\n")
        self.assertEqual(advancing.returncode, 0, advancing.stderr)
        self.assertEqual(advancing.stdout, b'0\n1\n2\n3\n4\n5\n')
        stalled = self.run_child("import time; print('started', flush=True); time.sleep(2)")
        self.assertEqual(stalled.returncode, 124, stalled.stderr)
        self.assertIn(b'no command output', stalled.stderr)

    def test_stalled_child_is_rejected_and_failure_propagates(self):
        stalled = self.run_child('import time; time.sleep(2)')
        self.assertEqual(stalled.returncode, 124, stalled.stderr)
        self.assertEqual(stalled.stdout, b'')
        self.assertIn(b'FAIL', stalled.stderr)
        failed = self.run_child('raise SystemExit(7)')
        self.assertEqual(failed.returncode, 7, failed.stderr)


if __name__ == '__main__':
    unittest.main()


class GroupSignalRaces(unittest.TestCase):
    def test_darwin_zombie_only_and_disappeared_groups_are_already_drained(self):
        for snapshot in ('42 Z\n99 S\n', '99 S\n'):
            with self.subTest(snapshot=snapshot), patch('sys.platform', 'darwin'), \
                    patch('os.killpg', side_effect=PermissionError(1, 'no signal target')), \
                    patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, stdout=snapshot)):
                signal_group(42, 9)

    def test_darwin_live_member_permission_failure_remains_fatal(self):
        with patch('sys.platform', 'darwin'), patch('os.killpg', side_effect=PermissionError(1, 'live target')), \
                patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, stdout='42 Z\n42 S\n')), \
                self.assertRaises(PermissionError):
            signal_group(42, 9)

    def test_unverifiable_group_is_not_admitted_as_drained(self):
        for failure in (subprocess.TimeoutExpired('ps', 1), OSError('unavailable')):
            with self.subTest(failure=failure), patch('sys.platform', 'darwin'), \
                    patch('os.killpg', side_effect=PermissionError(1, 'unknown target')), \
                    patch('subprocess.run', side_effect=failure), self.assertRaises(PermissionError):
                signal_group(42, 9)
        with patch('sys.platform', 'darwin'), patch('os.killpg', side_effect=PermissionError(1, 'unknown target')), \
                patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, stdout='malformed')), \
                self.assertRaises(PermissionError):
            signal_group(42, 9)

    def test_other_platform_permission_failure_is_not_reinterpreted(self):
        with patch('sys.platform', 'linux'), patch('os.killpg', side_effect=PermissionError(1, 'denied')), \
                patch('subprocess.run') as observe, self.assertRaises(PermissionError):
            signal_group(42, 9)
        observe.assert_not_called()
