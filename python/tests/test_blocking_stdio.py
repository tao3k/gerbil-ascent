# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Real pipe backpressure and exec identity controls for the oracle boundary."""
from pathlib import Path
import subprocess
import sys
import time
import unittest


class BlockingStdio(unittest.TestCase):
    wrapper = Path(__file__).parents[1] / "src/ascent_test_support/blocking_stdio.py"
    # Set inherited flags in a launcher, exactly as a VM can before exec.
    launcher = (
        "import os,sys\n"
        "for fd in (0,1,2): os.set_blocking(fd,False)\n"
        "os.execvp(sys.argv[1],sys.argv[1:])\n"
    )
    writer = (
        "import os,sys\n"
        "assert all(os.get_blocking(fd) for fd in (0,1,2))\n"
        "os.write(1,b'READY\\n')\n"
        "sys.stderr.buffer.write(b'x'*1048576); sys.stderr.buffer.flush()\n"
        "sys.stdout.buffer.write(b'row\\x00\\xff\\n'); sys.stdout.buffer.flush()\n"
        "raise SystemExit(int(sys.argv[1]))\n"
    )

    def test_backpressure_preserves_bytes_arguments_and_failure_exit(self):
        for status in (0, 7):
            with self.subTest(status=status):
                with subprocess.Popen(
                    [sys.executable, "-c", self.launcher, sys.executable,
                     str(self.wrapper), "--", sys.executable, "-c", self.writer,
                     str(status)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                ) as child:
                    self.assertEqual(child.stdout.readline(), b"READY\n")
                    # Let the real pipe fill before draining. No invented progress.
                    time.sleep(.1)
                    output, error = child.communicate(timeout=5)
                self.assertEqual(child.returncode, status)
                self.assertEqual(output, b"row\x00\xff\n")
                self.assertEqual(error, b"x" * 1048576)

    def test_unadapted_inheritance_is_rejected(self):
        result = subprocess.run(
            [sys.executable, "-c", self.launcher, sys.executable, "-c", self.writer, "0"],
            capture_output=True, timeout=5,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"AssertionError", result.stderr)

    def test_unadapted_full_pipe_cannot_complete(self):
        code = self.writer.replace("assert all(os.get_blocking(fd) for fd in (0,1,2))\n", "")
        with subprocess.Popen(
            [sys.executable, "-c", self.launcher, sys.executable, "-c", code, "0"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        ) as child:
            self.assertEqual(child.stdout.readline(), b"READY\n")
            time.sleep(.1)
            output, error = child.communicate(timeout=5)
        self.assertNotEqual(child.returncode, 0)
        self.assertNotEqual(error, b"x" * 1048576)
        self.assertEqual(output, b"")

    def test_missing_command_is_rejected(self):
        result = subprocess.run([sys.executable, str(self.wrapper)],
                                capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"expected a command", result.stderr)


if __name__ == "__main__":
    unittest.main()
