# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Independent Rust owners retain request limits and declarative source isolation."""
import os
import unittest
from unittest.mock import patch

from ascent import Engine, EngineError
from test_module_calls import decode


SOURCE = '''(ascent-fragment
  (relation input ((value exact-integer?)))
  (relation output ((value exact-integer?)))
  ((output V) <-- (input V)))'''


class ModuleLoadingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = Engine()
        cls.engine.describe()

    @classmethod
    def tearDownClass(cls):
        cls.engine.close()
        with cls().assertRaises((EngineError, ValueError)):
            cls.engine.describe()
        with Engine() as independent:
            cls().assertEqual(independent.describe()['abi'], 1)

    def test_repeated_engine_reuses_runtime_but_preserves_caller_limits(self):
        with Engine(max_request_bytes=4) as engine:
            self.assertEqual(engine.max_request_bytes, 4)
            self.assertIsNone(self.engine.max_request_bytes)
            with self.assertRaisesRegex(EngineError, 'caller request byte bound'):
                engine.dsl('(define-program (make) (sources) (outputs))', trusted=True)
            self.assertEqual(engine.describe()['abi'], 1)
            self.assertEqual(self.engine.describe()['abi'], 1)

    def test_reused_syntax_parent_keeps_program_state_and_failed_expansion_isolated(self):
        with self.engine.open_sources(SOURCE) as first:
            first.run(queries=['output'])
            first.replace({'input': [[1]]})
            with first.result(first.run(queries=['output'])) as result:
                self.assertEqual(decode(result.graph('output')), [[1]])
            with self.assertRaises(EngineError):
                self.engine.open_sources(SOURCE.replace('(input V)', '(input Missing)'))
            with self.engine.open_sources(SOURCE) as second:
                second.run(queries=['output'])
                second.replace({'input': [[2], [3]]})
                with second.result(second.run(queries=['output'])) as result:
                    self.assertEqual(sorted(decode(result.graph('output'))), [[2], [3]])
            with first.result(first.run(queries=['output'])) as result:
                self.assertEqual(decode(result.graph('output')), [[1]])
