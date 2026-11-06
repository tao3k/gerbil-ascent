# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""The package interpreter must preserve the native linker boundary."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest


class BuildEnvironmentTests(unittest.TestCase):
    def test_inherited_linker_cannot_override_native_toolchain(self):
        root = Path(__file__).resolve().parents[2]
        command = subprocess.check_output(['just', '--evaluate', 'gxi_command'], cwd=root, text=True).strip()
        with tempfile.TemporaryDirectory() as directory:
            fake = Path(directory) / 'ld'
            fake.write_text('#!/bin/sh\nexit 97\n')
            fake.chmod(0o755)
            environment = dict(os.environ, PATH=directory + ':' + os.environ['PATH'])
            expression = '(displayln (getenv "PATH"))'
            result = subprocess.run(['bash', '-c', command + ' -e ' + shlex.quote(expression)],
                                    cwd=root, env=environment, text=True, capture_output=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            child_path = result.stdout.strip().splitlines()[-1]
            resolved = shutil.which('ld', path=child_path)
            self.assertIsNotNone(resolved)
            self.assertNotEqual(Path(resolved).resolve(), fake.resolve())
            self.assertIn(resolved, ('/usr/bin/ld', '/bin/ld'))
