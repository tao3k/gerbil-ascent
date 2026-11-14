# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""The package interpreter must preserve the native linker boundary."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


class BuildEnvironmentTests(unittest.TestCase):
    def test_inherited_linker_cannot_override_native_toolchain(self):
        root = Path(__file__).resolve().parents[2]
        command = subprocess.check_output(['just', '--evaluate', 'gxi_command'], cwd=root, text=True).strip()
        with tempfile.TemporaryDirectory() as directory:
            fake = Path(directory) / 'ld'
            invoked = Path(directory) / 'unexpected-linker'
            fake.write_text('#!/bin/sh\nprintf unexpected > ' + shlex.quote(str(invoked)) + '\nexit 97\n')
            fake.chmod(0o755)
            source = Path(directory) / 'linker-control.c'
            binary = Path(directory) / 'linker-control'
            source.write_text('#include <stdio.h>\nint main(void) { puts("LINKER-BOUNDARY-OK"); return 0; }\n')
            environment = dict(os.environ, PATH=directory + ':' + os.environ['PATH'],
                               COMPILER_PATH=directory)
            expression = ('(import :std/misc/process) '
                          '(run-process ["cc" "-o" ' + json.dumps(str(binary), ensure_ascii=False) +
                          ' ' + json.dumps(str(source), ensure_ascii=False) + ']) '
                          '(display (run-process [' + json.dumps(str(binary), ensure_ascii=False) + ']))')
            result = subprocess.run(['bash', '-c', command + ' -e ' + shlex.quote(expression)],
                                    cwd=root, env=environment, text=True, capture_output=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('LINKER-BOUNDARY-OK', result.stdout.splitlines())
            self.assertFalse(invoked.exists(), 'the inherited linker was executed')
