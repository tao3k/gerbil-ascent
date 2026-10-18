# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Installed declarative definitions replace the downstream development shell."""
import os
import subprocess
import sys
import unittest

from ascent import Engine, EngineError

SOURCE = '''(define-evidence (make) (sources input) (outputs answer)
  (relation input ((value exact-integer?)) ((1)))
  (relation answer ((value exact-integer?)))
  ((answer X) <-- (input X)))'''


class DevelopmentShellTest(unittest.TestCase):
    def test_import_definitions_and_engine_call(self):
        script = '''from ascent import Engine
import sys
with Engine() as engine, engine.dsl(sys.argv[1], trusted=True) as session:
    assert session.run(result_format="typed-rows").value()["relations"]["answer"] == [[1]]
    assert not session.runtime().value()["schemeVm"]
'''
        env = {k: v for k, v in os.environ.items() if not k.startswith('GERBIL')}
        env['PATH'] = ''
        result = subprocess.run([sys.executable, '-c', script, SOURCE],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_source_reload_updates_exported_binding(self):
        with Engine() as engine:
            with engine.dsl(SOURCE, trusted=True) as original:
                with engine.dsl(SOURCE.replace('((1))', '((2))'), trusted=True) as current:
                    self.assertEqual(current.run(result_format='typed-rows').value()['relations']['answer'], [[2]])
                self.assertEqual(original.run(result_format='typed-rows').value()['relations']['answer'], [[1]])

    def test_invalid_expression_returns_nonzero_status(self):
        with Engine() as engine:
            for source in ('(missing-development-binding)', '(import :gerbil/runtime)',
                           '(def (answer) 1)'):
                with self.assertRaises(EngineError):
                    engine.dsl(source, trusted=True)
