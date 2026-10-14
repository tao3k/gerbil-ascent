"""Installed-wheel semantic migration: native DSL and typed Rust result authority."""
from pathlib import Path
import unittest
import ascent

FIXTURES = Path(__file__).resolve().parents[2] / 'ascent/tests/fixtures'
SOURCE = (FIXTURES / 'evidence-source.ss').read_text()
LATTICE = (FIXTURES / 'constructor-lattice.ss').read_text()
GRAPH = (FIXTURES / 'constructor-graph-values.ss').read_text()


class ConstructorSessions(unittest.TestCase):
    def setUp(self): self.engine = ascent.Engine(workers=4)
    def tearDown(self): self.engine.shutdown()

    def test_constructor_values_structural_dedup_and_transactional_source_replacement(self):
        values = [{'type': 'vector', 'value': [1, {'type': 'symbol', 'value': 'a'}]},
                  {'type': 'vector', 'value': [1, {'type': 'symbol', 'value': 'a'}]},
                  {'type': 'u8vector', 'value': [0, 255]},
                  {'type': 'number', 'value': '2/6'},
                  {'type': 'number', 'value': '1/3'}]
        with self.engine.evidence(SOURCE, 'make-evidence', values, trusted=True) as session:
            self.assertEqual(session.projection['status'], 'unsupported')
            self.assertEqual(session.fact_limits, {'input': 32, 'derived': 64, 'output': 96})
            self.assertEqual(set(session.queries), {'input', 'output'})
            receipt = session.run(queries=['output'])
            self.assertEqual(receipt['scalarProjection'], 'partial')
            with session.result(receipt) as result:
                graph = result.rows('output')['value']
                self.assertEqual(len([n for n in graph['nodes'] if n['type'] == 'vector']), 1)
                self.assertEqual(len([n for n in graph['nodes'] if n['type'] == 'u8vector']), 1)
                self.assertIn('1/3', str(graph))
                with self.assertRaises(ascent.EngineError): session.replace({'input': [[1, 2]]})
                self.assertEqual(result.rows('output')['value'], graph)
                with result.explanation('output') as proof:
                    self.assertIn('not a per-row proof', str(proof.graph))
            session.replace({'input': [[{'type': 'number', 'value': '7/2'}]]})
            with session.result(session.run(queries=['output'])) as result:
                with result.explanation('output') as proof:
                    self.assertIn('7/2', str(proof.graph))
                    self.assertNotIn('1/3', str(proof.graph))

    def test_original_lattice_constructor_and_default_explanation(self):
        with self.engine.evidence(LATTICE, 'make-lattice', [[0, 9], [0, 2], [1, 7]], trusted=True) as session:
            first = session.run(queries=['best'])
            self.assertEqual(first['relations']['best'], [[0, 2], [1, 7]])
            with session.result(first) as result:
                with result.explanation('best') as proof: self.assertIn('unsupported', str(proof.graph))
                with result.provenance('best') as proof:
                    self.assertEqual(proof.graph['status'], 'unsupported')
                    self.assertFalse(proof.verify())
            session.replace({'improve': [[0, 12]]})
            self.assertEqual(session.run(queries=['best'])['relations']['best'], [[0, 12]])

    def test_original_graph_values_and_opaque_result_reference_replacement(self):
        with self.engine.evidence(GRAPH, 'make-graph-values', trusted=True) as session:
            receipt = session.run()
            self.assertEqual(len(receipt['relations']['input']), 8)
            with session.result(receipt) as result:
                graph = result.rows('input')['value']
                kinds = {n['type'] for n in graph['nodes']}
                self.assertTrue({'vector', 'hash-table', 'opaque', 'symbol'} <= kinds)
                symbol_ids = [n['id'] for n in graph['nodes'] if n['type'] == 'symbol' and n.get('interned') is False]
                self.assertEqual(len(set(symbol_ids)), 2)
                opaque = next(i for i, v in enumerate(receipt['relations']['input']) if any(n['type'] == 'opaque' for n in v[0].get('nodes', [])))
                reference = result.reference('input', opaque, 0)
                session.replace({'input': [[reference]]})
                with self.assertRaises(ValueError): result.rows('input')
                with self.assertRaises(ValueError): session.replace({'input': [[reference]]})
            with session.result(session.run()) as result:
                self.assertIn('opaque', str(result.rows('input')))
                with result.explanation('input') as proof: self.assertIn('unsupported', str(proof.graph))

    def test_independent_provenance_survives_result_release_and_fails_on_generation_change(self):
        with self.engine.evidence(SOURCE, 'make-evidence', [1, 2], trusted=True) as session:
            result = session.result(session.run(queries=['output']))
            explanation = result.explanation('output')
            proof = result.provenance('output')
            result.close()
            self.assertEqual(proof.graph['status'], 'complete')
            self.assertTrue(proof.verify())
            self.assertIn('not a per-row proof', str(explanation.graph))
            session.replace({'input': []})
            with self.assertRaises(ValueError): _ = proof.graph
            with self.assertRaises(ValueError): _ = explanation.graph
            proof.close()
            explanation.close()
            with session.result(session.run(queries=['output'])) as result:
                with result.provenance('output') as absence: self.assertEqual(absence.graph['status'], 'closed-absent')
            for invalid in [0, -1, True]:
                with self.assertRaises(ascent.EngineError): ascent.ProvenanceLimits(max_steps=invalid)

    def test_foreign_result_handles_and_values_cannot_cross_session_authority(self):
        with self.engine.dsl(SOURCE, trusted=True) as module:
            with module.call('make-evidence', [1]) as a, module.call('make-evidence', [2]) as b:
                with a.open_session() as first, b.open_session() as second:
                    one, two = first.run(), second.run()
                    with self.assertRaises(ascent.EngineError): first.result(two)
                    with first.result(one) as result:
                        reference = result.reference('output', 0, 0)
                        with self.assertRaises(ascent.EngineError): second.replace({'input': [[reference]]})

    def test_constructor_loading_execution_and_checking_without_build_tools(self):
        import os
        from unittest.mock import patch
        with patch.dict(os.environ, {'PATH': '', 'CARGO': '', 'RUSTC': ''}):
            with self.engine.evidence(SOURCE, 'make-evidence', [7], trusted=True) as session:
                receipt = session.run(queries=['output'])
                self.assertEqual(receipt['relations']['output'], [[7]])
                with session.result(receipt) as result:
                    with result.provenance('output') as proof: self.assertTrue(proof.verify())
