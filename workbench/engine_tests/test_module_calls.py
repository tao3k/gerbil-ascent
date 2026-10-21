# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Public Graph composition, source updates and independent native owner leases."""
import unittest
from ascent import Engine, EngineError

def decode(graph):
    nodes = {node['id']: node for node in graph['nodes']}
    def item(value):
        if 'ref' in value: value = nodes[value['ref']]
        kind = value['type']
        if kind == 'null': return []
        if kind == 'number': return int(value['value'])
        if kind in ('string', 'symbol', 'boolean'): return value['value']
        if kind == 'vector': return [item(v) for v in value['items']]
        if kind == 'pair': return [item(value['car']), *item(value['cdr'])]
        raise AssertionError(kind)
    return item(graph['root'])

SOURCE = '''(define-program (make) (sources input) (outputs output)
  (relation input ((x integer?)) ((1))) (relation output ((x integer?)))
  ((output X) <-- (input X)))'''

class ModuleCallTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.engine = Engine()
    @classmethod
    def tearDownClass(cls): cls.engine.close()

    def test_upstream_operator_composition_retained_session_and_withdrawal(self):
        with self.engine.source_graph('edge', 2, [[0, 1], [1, 2]]) as source:
            with source.project([1]) as graph, graph.open_session('targets') as session:
                self.assertEqual(session.run()['relations']['targets'], [[1], [2]])
                session.replace({'edge': [[7, 8]]})
                self.assertEqual(session.run()['relations']['targets'], [[8]])
                with self.assertRaises(EngineError): session.replace({'edge': [[1]]})
                self.assertEqual(session.run()['relations']['targets'], [[8]])
                session.replace({'edge': []})
                self.assertEqual(session.run()['relations']['targets'], [])

    def test_cross_module_lattice_program_without_wire_projection(self):
        source = '''(define-program (make) (sources input) (outputs best)
          (relation input ((key integer?) (score integer?)) ((0 9) (0 2) (1 7)))
          (lattice best ((key integer?) (score integer?)) () min)
          ((best K V) <-- (input K V)))'''
        with self.engine.rules(source, trusted=True) as session:
            with session.result(session.run()) as result:
                self.assertEqual(decode(result.graph('best')), [[0, 2], [1, 7]])
        with self.engine.core_rules(source, trusted=True) as owner:
            self.assertEqual(owner.run(result_format='typed-rows').value()['relations']['best'], [[0, 2], [1, 7]])

    def test_multiple_native_return_values_and_prepared_query(self):
        source = '''(define-program (multiple) (sources) (outputs left right)
          (relation left ((x integer?)) ((3))) (relation right ((x integer?)) ((5))))'''
        with self.engine.dsl(source, trusted=True) as owner:
            value = owner.run(result_format='typed-rows', queries=['left', 'right'])
            try:
                self.assertEqual(value.value()['relations'], {'left': [[3]], 'right': [[5]]})
                self.assertEqual(value.value(), value.value())
            finally: value.close()
            with self.assertRaises(EngineError): value.value()

    def test_native_prepared_change_and_retained_operator_updates(self):
        source = '''(define-program (change) (sources previous current) (outputs old new delta)
          (relation previous ((key integer?) (value integer?)) ((0 1)))
          (relation current ((key integer?) (value integer?)) ((0 1) (2 3)))
          (relation old ((x integer?))) (relation new ((x integer?))) (relation delta ((x integer?)))
          ((old V) <-- (previous K V)) ((new V) <-- (current K V))
          ((delta V) <-- (new V) (not (old V))))'''
        with self.engine.rules(source, trusted=True) as session:
            self.assertEqual(session.run()['relations'], {'old': [[1]], 'new': [[1], [3]], 'delta': [[3]]})
            session.replace({'current': [[7, 8]]})
            self.assertEqual(session.run()['relations'], {'old': [[1]], 'new': [[8]], 'delta': [[8]]})

    def test_unknown_export_failed_call_released_and_foreign_references(self):
        with self.engine.source_graph('source', 1, [[1]]) as graph:
            with Engine() as foreign, foreign.source_graph('other', 1, [[1]]) as other:
                with self.assertRaises(ValueError): graph.union(other)
            with graph.open_session('answer') as session:
                receipt = session.run()
                with self.assertRaises(EngineError): session.run(queries=['identity'])
                result = session.result(receipt)
                reference = result.reference('answer', 0, 0)
                result.close()
                with self.assertRaises(EngineError): reference.scalar()
                with self.assertRaises(EngineError): result.reference('answer', 0, 0)
            with self.assertRaises(EngineError): session.run()
        with self.assertRaises(ValueError): graph.project([0])

    def test_owner_capacity_releases_and_does_not_select_python_fallback(self):
        with self.engine.rules(SOURCE, trusted=True) as session:
            results = [session.result(session.run()) for _ in range(64)]
            try:
                with self.assertRaisesRegex(EngineError, 'owner limit'): session.run()
                results.pop().close()
                with session.result(session.run()) as value:
                    self.assertEqual(value.rows('output')['rows'], [[1]])
            finally:
                for value in results: value.close()
            self.assertTrue(session.run()['complete'])

    def test_independent_explanation_lifetime_and_repeated_cleanup(self):
        with self.engine.rules(SOURCE, trusted=True) as session:
            with session.result(session.run()) as result:
                for _ in range(70):
                    with result.explanation('output') as proof:
                        self.assertTrue(proof.current)
                        self.assertTrue(proof.verify())
                        self.assertIn('dependencies', proof.graph)
                        self.assertIn('gap', proof.graph)
                    with self.assertRaises(EngineError): _ = proof.graph
                self.assertEqual(result.source_generation, 0)

if __name__ == '__main__': unittest.main()
