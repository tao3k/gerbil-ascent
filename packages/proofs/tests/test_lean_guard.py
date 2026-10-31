# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""The locked LeanPoo Guard must reap real failures without helper-thread leaks."""
import os
import shlex
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from types import SimpleNamespace

import ascent_workbench.formal as formal

from ascent_workbench.formal import Runner, capacity
from ascent_workbench.lean_guard import process_guard, run_checked


class LeanGuardTests(unittest.TestCase):
    def run_guard(self, program, seconds=2):
        lines = []
        code, receipt = run_checked([sys.executable, "-u", "-c", program], seconds, lines.append)
        return code, b"".join(lines), receipt

    def test_recursion_is_bounded_reaped_and_has_no_helper_thread_leak(self):
        before = {thread.ident for thread in threading.enumerate()}
        code, output, receipt = self.run_guard(
            'import signal;signal.signal(signal.SIGTERM,signal.SIG_IGN);'
            'print("started",flush=True)\nwhile True: pass', 0.2)
        self.assertEqual(code, 124)
        self.assertEqual(output, b"started\n")
        self.assertTrue(receipt["direct_child_reaped"])
        self.assertEqual(receipt["additional_helper_threads"], 0)
        self.assertEqual({thread.ident for thread in threading.enumerate()}, before)

    def test_nonzero_exit_and_output_remain_exact(self):
        code, output, receipt = self.run_guard('print("control");raise SystemExit(7)')
        self.assertEqual(code, 7)
        self.assertEqual(output, b"control\n")
        self.assertEqual(receipt["returncode"], 7)
        self.assertGreaterEqual(receipt["cpu_seconds"], 0)
        self.assertEqual(len(receipt["guard_sha256"]), 64)

    def test_exited_leader_cannot_leave_descendant_work(self):
        with tempfile.TemporaryDirectory() as temporary:
            marker = Path(temporary) / "escaped-work"
            child = ('import signal,time,pathlib;signal.signal(signal.SIGTERM,signal.SIG_IGN);'
                     f'time.sleep(0.8);pathlib.Path({str(marker)!r}).touch();time.sleep(5)')
            code, output, _ = self.run_guard(
                f'import subprocess,sys;subprocess.Popen([sys.executable,"-c",{child!r}]);'
                'print("leader-done",flush=True)')
            self.assertEqual(code, 0)
            self.assertEqual(output, b"leader-done\n")
            time.sleep(0.9)
            self.assertFalse(marker.exists())

    def test_output_failure_keeps_exception_and_reaps_direct_child(self):
        guard, _, _ = process_guard()
        before = {thread.ident for thread in threading.enumerate()}
        failure = RuntimeError("broken sink")
        pid = []
        def refuse(line):
            pid.append(int(line))
            raise failure
        with self.assertRaises(RuntimeError) as caught:
            run_checked([sys.executable, "-u", "-c",
                         'import os,time;print(os.getpid(),flush=True);time.sleep(5)'], 2, refuse)
        self.assertIs(caught.exception, failure)
        with self.assertRaises(ProcessLookupError):
            os.kill(pid[0], 0)
        self.assertEqual({thread.ident for thread in threading.enumerate()}, before)
        self.assertIsNotNone(guard.collect)

    def test_render_output_is_separate_from_guard_receipt_and_diagnostics(self):
        with tempfile.TemporaryFile() as diagnostics:
            lines = []
            code, _ = run_checked([sys.executable, "-u", "-c",
                                   'import sys;print("source");print("diagnostic",file=sys.stderr)'],
                                  2, lines.append, stderr=diagnostics)
            diagnostics.seek(0)
            self.assertEqual(code, 0)
            self.assertEqual(b"".join(lines), b"source\n")
            self.assertEqual(diagnostics.read(), b"diagnostic\n")

    def test_lean_entry_refuses_a_non_source_path(self):
        result = subprocess.run([sys.executable, "-m", "ascent_workbench.lean_guard", "file", "input.txt"],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertIn("expected an existing Lean source", result.stderr)


class FormalWorkerCeilingTests(unittest.TestCase):
    def test_ceiling_only_reduces_detected_capacity(self):
        with patch.dict("os.environ", {}, clear=False):
            os.environ.pop("ASCENT_FORMAL_WORKERS", None)
            detected = capacity()
        with patch.dict("os.environ", {"ASCENT_FORMAL_WORKERS": "1"}):
            self.assertEqual(capacity(), 1)
        with patch.dict("os.environ", {"ASCENT_FORMAL_WORKERS": str(detected + 20)}):
            self.assertEqual(capacity(), detected)

    def test_invalid_ceiling_is_refused(self):
        for value in ("0", "-1", "", "unlimited"):
            with self.subTest(value=value), patch.dict("os.environ", {"ASCENT_FORMAL_WORKERS": value}):
                with self.assertRaises(ValueError):
                    capacity()


class NestedLeanGuardTests(unittest.TestCase):
    def runner(self, temporary, program, seconds):
        folder = Path(temporary)
        lake = folder / "lake"
        lake.write_text("#!/bin/sh\nexec " + shlex.join([sys.executable, "-u", "-c", program]) + "\n")
        lake.chmod(0o700)
        runner = Runner.__new__(Runner)
        runner.output = folder
        runner.deadline = time.monotonic() + seconds
        runner.environment = dict(os.environ, PATH=str(folder) + os.pathsep + os.environ["PATH"])
        return runner

    def test_parent_timeout_reaps_nested_compiler_group(self):
        before = {thread.ident for thread in threading.enumerate()}
        with tempfile.TemporaryDirectory() as temporary:
            marker = Path(temporary) / "compiler-pid"
            program = ('import os,signal,pathlib,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);'
                       f'pathlib.Path({str(marker)!r}).write_text(str(os.getpid()));'
                       'print("compiler-started",flush=True);time.sleep(10)')
            runner = self.runner(temporary, program, 3)
            def after_compiler_ready():
                # Test cancellation of a running compiler, independently of
                # import/startup latency. Failure to become ready remains fatal.
                startup = time.monotonic() + 3
                while not marker.exists():
                    if time.monotonic() >= startup:
                        self.fail("compiler did not become ready")
                    time.sleep(0.01)
                runner.deadline = time.monotonic() + 0.2
                return time.monotonic()
            with patch.object(formal, "time", SimpleNamespace(monotonic=after_compiler_ready)):
                with self.assertRaises(subprocess.TimeoutExpired):
                    runner.run(["lake", "env", "lean", "--run", "RenderScc.lean", "scheme"], "canceled")
            self.assertTrue(marker.is_file(), "compiler was not reached")
            with self.assertRaises(ProcessLookupError):
                os.kill(int(marker.read_text()), 0)
        self.assertEqual({thread.ident for thread in threading.enumerate()}, before)

    def test_source_stdout_excludes_guard_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            runner = self.runner(temporary, 'print("source-body")', 3)
            code, source = runner.run(
                ["lake", "env", "lean", "--run", "RenderScc.lean", "scheme"], "render")
            self.assertEqual(code, 0)
            self.assertEqual(source, "source-body\n")
            diagnostics = (Path(temporary) / "render.stderr.out").read_text()
            self.assertIn("LEAN-GUARD-RECEIPT", diagnostics)
            self.assertIn('"additional_helper_threads": 0', diagnostics)
