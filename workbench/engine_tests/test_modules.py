# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Declarative constructors retain full native values, sources and explanation leases."""
import unittest
from ascent import Engine, EngineError

COPY = '''(define-evidence (make-values) (sources input) (outputs input output)
  (relation input (value) ((3))) (relation output (value))
  ((output X) <-- (input X)))'''

GRAPHS = '''(define-evidence (graphs) (sources input) (outputs input)
  (relation input (value)
    (((object-graph (ref 0) ((0 vector (ref 0)))))
     ((object-graph (ref 0) ((0 vector (ref 1) (ref 1)) (1 vector 17))))
     ((object-graph (ref 0) ((0 table ((ref 1) (ref 2))) (1 text "same") (2 vector 17))))
     ((object-graph (ref 0) ((0 opaque "fixed-core-token"))))
     ((object-graph (ref 0) ((0 symbol "scoped" #f))))
     ((object-graph (ref 0) ((0 symbol "scoped" #f)))))))'''

class ModuleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.engine = Engine()
    @classmethod
    def tearDownClass(cls): cls.engine.close()

    def test_hygienic_constructor_native_values_and_explanation(self):
        source = COPY.replace('((3))', '''(
          ((object-graph (ref 0) ((0 vector 1 (ref 1)) (1 symbol "a" #t))))
          ((object-graph (ref 0) ((0 u8vector 0 255)))) (1/3))''')
        with self.engine.evidence(source, trusted=True) as session:
            first = session.run()
            self.assertEqual(first['scalarProjection'], 'partial')
            with session.result(first) as result:
                graph = result.graph('output')
                self.assertTrue({'vector', 'u8vector', 'pair'} <= {n['type'] for n in graph['nodes']})
                self.assertIn('1/3', str(graph))
                explanation = result.explanation('output')
                self.assertEqual(explanation.graph['status'], 'recorded-only')
                self.assertTrue(explanation.graph['dependencies'])
                with self.assertRaises(TypeError): session.result(explanation)
            self.assertTrue(explanation.current)
            explanation.close()
            session.replace({'input': [[7]]})
            with session.result(session.run()) as updated:
                self.assertEqual(updated.rows('output')['rows'], [[7]])
                with updated.explanation('output') as proof:
                    self.assertIn([[7]], [r['rows'] for r in proof.graph['sources'] if r['source']])

    def test_upstream_lattice_aggregate_and_operator(self):
        source = '''(define-evidence (best) (sources input) (outputs best)
          (relation input ((key integer?) (score integer?)) ((0 9) (0 2) (1 7)))
          (lattice best ((key integer?) (score integer?)) () min)
          ((best K V) <-- (input K V)))'''
        with self.engine.evidence(source, trusted=True) as session:
            self.assertEqual(session.run()['relations']['best'], [[0, 2], [1, 7]])
        graph = {'algorithm': 'projection', 'source': 'edge', 'width': 2,
                 'rows': [[0, 1], [1, 2]], 'output': 'targets', 'captures': {'columns': [1]}}
        with self.engine.core_graph(graph, trusted=True) as session:
            self.assertEqual(session.run(result_format='typed-rows').value()['relations']['targets'], [[1], [2]])
            session.replace({'edge': [[3, 4]]}).value()
            self.assertEqual(session.run(result_format='typed-rows').value()['relations']['targets'], [[4]])
        mean = '''(define-evidence (average) (sources input) (outputs average)
          (relation input ((value integer?)) ((1) (2) (4)))
          (relation average ((value number?)))
          ((average N) <-- (aggregate N gerbil-ascent-mean (V) (input V))))'''
        with self.engine.evidence(mean, trusted=True) as session:
            self.assertAlmostEqual(session.run()['relations']['average'][0][0], 7 / 3)

    def test_closed_session_and_wrong_owner(self):
        session = self.engine.evidence(COPY, trusted=True)
        receipt = session.run()
        result = session.result(receipt)
        with self.engine.evidence(COPY, trusted=True) as other:
            other.run()
            with self.assertRaises(EngineError): other.result(receipt)
        session.close()
        with self.assertRaises(EngineError): result.rows('output')
        result.close()

    def test_rejected_update_and_failed_constructor_preserve_runtime(self):
        for name in ('missing-constructor', 'identity'):
            with self.assertRaises(EngineError): self.engine.evidence(COPY, name, trusted=True)
        with self.engine.evidence(COPY, trusted=True) as session:
            first = session.run()
            with session.result(first) as result:
                with self.assertRaises(EngineError): session.replace({'input': [[1, 2]]})
                self.assertEqual(result.source_generation, first['sourceGeneration'])
                second = session.run()
                self.assertTrue(second['nativeResultReused'])
                self.assertEqual(first['sourceGeneration'], second['sourceGeneration'])
                session.result(second).close()

    def test_shared_cyclic_and_opaque_native_values(self):
        with self.engine.evidence(GRAPHS, trusted=True) as session:
            with session.result(session.run()) as result:
                nodes = result.graph('input')['nodes']
                self.assertTrue({'vector', 'hash-table', 'opaque', 'pair'} <= {n['type'] for n in nodes})
                self.assertTrue(any(n['type'] == 'vector' and n['items'] == [{'ref': n['id']}] for n in nodes))
                self.assertTrue(any(n['type'] == 'vector' and len(n['items']) == 2 and n['items'][0] == n['items'][1] for n in nodes))
                symbols = [n for n in nodes if n['type'] == 'symbol' and n['value'] == 'scoped']
                self.assertEqual(len(symbols), 2)
                self.assertNotEqual(symbols[0]['id'], symbols[1]['id'])
                self.assertTrue(all(not n['interned'] for n in symbols))
                objects = session.run()['relations']['input']
                index = next(i for i, row in enumerate(objects) if 'fixed-core-token' in str(row[0].graph))
                reference = result.reference('input', index, 0)
                with self.engine.evidence(GRAPHS, trusted=True) as other:
                    with self.assertRaises(EngineError): other.replace({'input': [[reference]]})
                session.replace({'input': [[reference]]})
                with self.assertRaises(EngineError): result.rows('input')
            with session.result(session.run()) as updated:
                self.assertIn('fixed-core-token', str(updated.graph('input')))

    def test_execution_program_declares_observation_sources(self):
        source = '''(define-evidence (execution)
          (sources required_step observed_step) (outputs checked_step missing_step)
          (relation required_step ((step string?)))
          (relation observed_step ((step string?) (outcome string?) (capability string?)))
          (relation checked_step ((step string?))) (relation missing_step ((step string?)))
          ((checked_step S) <-- (observed_step S (lit "PASS") C))
          ((missing_step S) <-- (required_step S) (not (checked_step S))))'''
        with self.engine.evidence(source, trusted=True) as session:
            self.assertEqual({r['name'] for r in session.descriptors if r['source']}, {'required_step', 'observed_step'})
            session.replace({'required_step': [['finished'], ['missing']],
                             'observed_step': [['finished', 'PASS', 'test']]})
            receipt = session.run()
            self.assertEqual(receipt['relations']['checked_step'], [['finished']])
            self.assertEqual(receipt['relations']['missing_step'], [['missing']])
            with session.result(receipt) as result:
                with result.explanation('missing_step') as proof:
                    self.assertEqual(proof.graph['status'], 'recorded-only')
                    self.assertIn('host authorization', proof.graph['gap'])

if __name__ == '__main__': unittest.main()
