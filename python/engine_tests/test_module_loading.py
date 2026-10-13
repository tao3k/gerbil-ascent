# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Actual CFFI initialization reuse and isolated repeated DSL expansion."""
import os
import unittest
from unittest.mock import patch

from ascent_engine import Engine, EngineError
from test_module_calls import decode


SOURCE = '''(ascent-fragment
  (relation input ((value exact-integer?)))
  (relation output ((value exact-integer?)))
  ((output V) <-- (input V)))'''


class ModuleLoadingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.library = os.environ['ASCENT_ENGINE_LIBRARY']
        cls.engine = Engine(cls.library)

    @classmethod
    def tearDownClass(cls):
        cls.engine.shutdown()
        with cls().assertRaisesRegex(EngineError, 'runtime shut down'):
            Engine(cls.library)

    def test_repeated_engine_reuses_runtime_but_preserves_caller_limits(self):
        with patch('ascent_engine._preserve_host_io',
                   side_effect=AssertionError('re-entered native initialization')):
            engine = Engine(self.library, max_request_bytes=10)
        self.assertEqual(engine.max_request_bytes, 10)
        self.assertIsNone(self.engine.max_request_bytes)
        with self.assertRaisesRegex(EngineError, 'caller input byte bound'):
            engine.request({'operation': 'describe'})
        self.assertEqual(self.engine.request({'operation': 'describe'})['abi'], 1)

    def test_reused_syntax_parent_keeps_program_state_and_failed_expansion_isolated(self):
        with self.engine.open_sources(SOURCE) as first:
            first.run(queries=['output'])
            first.replace({'input': [[1]]})
            with first.result(first.run(queries=['output'])) as result:
                self.assertEqual(decode(result.rows('output')['value']), [[1]])
            with self.assertRaises(EngineError):
                self.engine.open_sources(SOURCE.replace('(input V)', '(input Missing)'))
            with self.engine.open_sources(SOURCE) as second:
                second.run(queries=['output'])
                second.replace({'input': [[2], [3]]})
                with second.result(second.run(queries=['output'])) as result:
                    self.assertEqual(sorted(decode(result.rows('output')['value'])), [[2], [3]])
            with first.result(first.run(queries=['output'])) as result:
                self.assertEqual(decode(result.rows('output')['value']), [[1]])
