# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Real C ABI module controls. Run in a fresh process with a matched artifact."""
import os
import unittest
from ascent_engine import Engine, EngineError

MODULE = ':gerbil-ascent/t/qualification/evidence-api-module'


class NativeModuleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = Engine(os.environ.get('ASCENT_NATIVE_LIBRARY'))

    @classmethod
    def tearDownClass(cls):
        cls.engine.shutdown()

    def test_hygienic_constructor_native_values_and_explanation(self):
        values = [{'type': 'vector', 'value': [1, {'type': 'symbol', 'value': 'a'}]},
                  {'type': 'u8vector', 'value': [0, 255]},
                  {'type': 'number', 'value': '1/3'}]
        with self.engine.open_module(MODULE, 'make-values', values) as session:
            self.assertEqual(session.projection['status'], 'unsupported')
            first = session.run(queries=['output'])
            self.assertTrue(first['complete'])
            self.assertEqual(first['scalarProjection'], 'partial')
            with session.result(first) as result:
                encoded = result.rows('output')['value']
                kinds = {node['type'] for node in encoded['nodes']}
                self.assertTrue({'vector', 'u8vector', 'pair'} <= kinds)
                self.assertIn('1/3', str(encoded))
                explanation = result.explain('output')
                self.assertIn('recorded-only', str(explanation))
                self.assertIn('dependencies', str(explanation))
                with self.assertRaises(EngineError):
                    self.engine.request({'operation': 'native-result', 'handle': session.handle,
                                         'result': explanation['explanationHandle'], 'action': 'rows',
                                         'relation': 'output'})
                self.engine.request({'operation': 'native-result', 'handle': session.handle,
                                     'result': explanation['explanationHandle'], 'action': 'release'})
                second = session.run(queries=['output'])
                self.assertTrue(second['nativeResultReused'])
                session.result(second).close()
                session.replace({'input': [[{'type': 'number', 'value': '7/2'}]]})
                with self.assertRaises(EngineError): result.rows('output')
                with session.result(session.run(queries=['output'])) as updated:
                    self.assertIn('7/2', str(updated.rows('output')))
                    explanation = updated.explain('output')
                    self.assertIn('7/2', str(explanation))
                    self.assertNotIn('1/3', str(explanation))
                    self.engine.request({'operation': 'native-result', 'handle': session.handle,
                                         'result': explanation['explanationHandle'], 'action': 'release'})

    def test_upstream_lattice_aggregate_and_operator(self):
        for constructor, arguments, relation, expected in (
            ('make-lattice', [[0, 9], [0, 2], [1, 7]], 'best', [[0, 2], [1, 7]]),
            ('make-operator', [[0, 1], [1, 2]], 'targets', [[1], [2]]),
        ):
            with self.subTest(constructor=constructor):
                with self.engine.open_module(MODULE, constructor, arguments) as session:
                    receipt = session.run(queries=[relation])
                    self.assertTrue(receipt['complete'])
                    self.assertEqual(sorted(receipt['relations'][relation]), expected)
                    session.result(receipt).close()
                    if constructor == 'make-operator':
                        session.replace({'edge': [[3, 4]]})
                        updated = session.run(queries=['targets'])
                        self.assertEqual(updated['relations']['targets'], [[4]])
                        session.result(updated).close()
        with self.engine.open_module(MODULE, 'make-aggregate', [1, 2, 4]) as session:
            receipt = session.run(queries=['average'])
            self.assertTrue(receipt['complete'])
            with session.result(receipt) as result:
                graph = result.rows('average')['value']
                numbers = [node['car']['value'] for node in graph['nodes']
                           if node['type'] == 'pair' and node['car'].get('type') == 'number']
                self.assertEqual(len(numbers), 1)
                self.assertAlmostEqual(float(numbers[0]), 7 / 3)

    def test_closed_session_and_wrong_owner(self):
        session = self.engine.open_module(MODULE, 'make-values', [1])
        receipt = session.run()
        result = session.result(receipt)
        with self.engine.open_module(MODULE, 'make-values', [2]) as other:
            with self.assertRaises(EngineError):
                self.engine.request({'operation': 'native-result', 'handle': other.handle,
                                     'result': result.handle, 'action': 'rows', 'relation': 'output'})
        session.close()
        with self.assertRaises(ValueError): result.rows('output')
        result.close()

    def test_rejected_update_and_failed_constructor_preserve_runtime(self):
        with self.assertRaises(EngineError):
            self.engine.open_module(MODULE, 'missing-constructor')
        with self.assertRaises(EngineError):
            self.engine.open_module(MODULE, 'identity', [1])
        with self.engine.open_module(MODULE, 'make-values', [3]) as session:
            first = session.run(queries=['output'])
            with session.result(first) as result:
                with self.assertRaises(EngineError): session.replace({'input': [[1, 2]]})
                self.assertEqual(result.rows('output')['sourceGeneration'], first['sourceGeneration'])
                second = session.run(queries=['output'])
                self.assertTrue(second['nativeResultReused'])
                self.assertEqual(first['sourceGeneration'], second['sourceGeneration'])
                session.result(second).close()

    def test_shared_cyclic_and_opaque_native_values(self):
        with self.engine.open_module(MODULE, 'make-graph-values') as session:
            with session.result(session.run(queries=['input'])) as result:
                graph = result.rows('input')['value']
                nodes = graph['nodes']
                kinds = {node['type'] for node in nodes}
                self.assertTrue({'vector', 'hash-table', 'opaque', 'pair'} <= kinds)
                self.assertTrue(any(node['type'] == 'vector' and node['items'] == [{'ref': node['id']}]
                                    for node in nodes))
                self.assertTrue(any(node['type'] == 'vector' and len(node['items']) == 2
                                    and node['items'][0] == node['items'][1] for node in nodes))
                opaque = next(node for node in nodes if node['type'] == 'opaque')
                symbols = [node for node in nodes if node['type'] == 'symbol'
                           and node['value'] == 'scoped']
                self.assertEqual(len(symbols), 2)
                self.assertNotEqual(symbols[0]['id'], symbols[1]['id'])
                self.assertTrue(all(not node['interned'] for node in symbols))
                session.replace({'input': [[{'type': 'reference', 'result': result.handle,
                                             'node': opaque['id']}]]})
                with self.assertRaises(EngineError): result.rows('input')
            with session.result(session.run(queries=['input'])) as updated:
                self.assertIn('native-reference-only', str(updated.rows('input')))

    def test_execution_program_declares_observation_sources(self):
        with self.engine.open_module(':gerbil-ascent/evidence/execution',
                                     'make-execution-evidence') as session:
            sources = {row['name'] for row in session.descriptors if row['source']}
            self.assertIn('required_step', sources)
            self.assertIn('observed_step', sources)
            self.assertNotIn('checked_step', sources)
            session.result(session.run()).close()
            session.replace({'required_step': [['finished'], ['missing']],
                             'observed_step': [['finished', 'PASS', 'native.test']]})
            receipt = session.run(queries=['checked_step', 'missing_step'])
            self.assertEqual(receipt['relations']['checked_step'], [['finished']])
            self.assertEqual(receipt['relations']['missing_step'], [['missing']])
            with session.result(receipt) as result:
                proof = result.explain('missing_step')
                self.assertIn('source refinement', str(proof))
                self.engine.request({'operation': 'native-result', 'handle': session.handle,
                                     'result': proof['explanationHandle'], 'action': 'release'})


if __name__ == '__main__':
    unittest.main()
