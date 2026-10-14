# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""The linked shell must retain upstream top-level and source reload behavior."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class DevelopmentShellTest(unittest.TestCase):
    def run_shell(self, source):
        root = Path(__file__).parents[2]
        executable = os.environ.get('ASCENT_DEVELOP_EXECUTABLE', root / '.gerbil/bin/ascent-develop')
        return subprocess.run([str(executable), '--eval', source],
                              env=dict(os.environ, GERBIL_PATH=str(root / '.gerbil')),
                              capture_output=True, text=True, timeout=20)

    def test_import_definitions_and_engine_call(self):
        result = self.run_shell('''(import :std/encoding/json)
          (def request (hash ("operation" "describe")))
          (displayln (ascent-engine-dispatch (json->string request)))''')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout.strip())['abi'], 1)

    def test_source_reload_updates_exported_binding(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'scenario.ss'
            source.write_text('(export answer) (def (answer) 1)\n')
            # These generated values contain no quotes or shell interpolation;
            # the Scheme reader receives a pathname and module source string.
            path = json.dumps(str(source))
            changed = json.dumps('(export answer) (def (answer) 2)')
            result = self.run_shell(f'''(import {path}) (displayln (answer))
              (call-with-output-file [path: {path} truncate: #t]
                (lambda (port) (display {changed} port)))
              (reload! {path}) (displayln (answer))''')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stdout.splitlines(), ['1', '2'])

    def test_invalid_expression_returns_nonzero_status(self):
        result = self.run_shell('(missing-development-binding)')
        self.assertNotEqual(result.returncode, 0)
