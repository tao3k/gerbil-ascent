"""Python-only declarative components, fixed Graph algorithms and owned results."""
import unittest
from ascent import Engine, EngineError
from test_module_calls import decode

SOURCE = '''
(defrules copy-rule () ((_ from to) ((to X) <-- (from X))))
(define-evidence (make-evidence)
  (sources input) (outputs output)
  (relation input ((value exact-integer?)) ((1) (2)))
  (relation output ((value exact-integer?)))
  (copy-rule input output))
'''

class ModuleSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.engine = Engine()
    @classmethod
    def tearDownClass(cls): cls.engine.close()

    def test_authorization_required_by_python_and_native(self):
        for operation in (self.engine.dsl, self.engine.evidence):
            with self.assertRaisesRegex(EngineError, 'trusted'):
                operation(SOURCE)
        self.assertFalse(hasattr(self.engine, 'request'))
        self.assertFalse(hasattr(self.engine, 'register_module'))

    def test_macro_import_constructor_update_withdrawal_and_explanation(self):
        with self.engine.evidence(SOURCE, 'make-evidence', trusted=True) as session:
            with session.result(session.run()) as result:
                self.assertEqual(decode(result.graph('output')), [[1], [2]])
                proof = result.explanation('output')
            self.assertEqual(proof.graph['status'], 'recorded-only')
            self.assertTrue(proof.current)
            proof.close()
            session.replace({'input': [[8]]})
            with session.result(session.run()) as result:
                self.assertEqual(decode(result.graph('output')), [[8]])
            session.replace({'input': []})
            with session.result(session.run()) as result:
                self.assertEqual(decode(result.graph('output')), [])
        with self.assertRaises(EngineError): session.run()

    def test_closures_cycles_foreign_and_released_values(self):
        # Fixed projection captures replace runtime closure production.
        with self.engine.source_graph('input', 2, [[7, 12]]) as source:
            with self.engine.projection_graph(2, [1]) as function:
                with function.apply(source) as graph, graph.open_session('answer') as session:
                    with session.result(session.run()) as result:
                        self.assertEqual(result.rows('answer')['rows'], [[12]])
                        reference = result.reference('answer', 0, 0)
                    with self.assertRaises(EngineError): reference.scalar()
                with self.assertRaises(ValueError): function.apply(graph)
        with Engine() as foreign, foreign.source_graph('foreign', 2, [[0, 5]]) as input:
            with self.engine.projection_graph(2, [1]) as function:
                with self.assertRaises(ValueError): function.apply(input)
        for code in ('(def (make n) (lambda (x) (+ n x)))', '(set! x 1)'):
            with self.assertRaises(EngineError): self.engine.dsl(code, trusted=True)
        cyclic = '''(define-evidence (cycle) (sources) (outputs output)
          (relation output (value) (( (object-graph (ref 0) ((0 vector (ref 0)))) ))))'''
        with self.engine.evidence(cyclic, trusted=True) as session:
            with session.result(session.run()) as result:
                graph = result.graph('output')
                vector = next(node for node in graph['nodes'] if node['type'] == 'vector')
                self.assertEqual(vector['items'], [{'ref': vector['id']}])

    def test_isolated_module_names_and_export_boundaries(self):
        with self.engine.evidence(SOURCE, trusted=True) as first:
            with self.engine.evidence(SOURCE.replace('((1) (2))', '((99))'), trusted=True) as second:
                self.assertEqual(second.run()['relations']['output'], [[99]])
                with self.assertRaises(EngineError): second.run(queries=['identity'])
            self.assertEqual(first.run()['relations']['output'], [[1], [2]])

    def test_invalid_source_and_failed_load_do_not_create_usable_owner(self):
        for source in ('(import :gerbil/core)', '(module scene (import :gerbil/core))',
                       '(export make-evidence)', '(unknown-dsl-form)'):
            with self.assertRaises(EngineError): self.engine.dsl(source, trusted=True)
        with self.engine.evidence(SOURCE, trusted=True) as session:
            self.assertEqual(session.run()['relations']['output'], [[1], [2]])

    def test_consumer_definitions_have_no_scheme_import_module_or_build(self):
        for token in ('(import', '(module', '(export', 'gxc', 'gerbil.pkg'):
            self.assertNotIn(token, SOURCE)
        with self.engine.dsl(SOURCE, trusted=True) as owner:
            with owner.run(result_format='typed-rows') as value:
                self.assertEqual(value.value()['relations']['output'], [[1], [2]])
            with self.assertRaises(EngineError): value.value()
        with self.assertRaises(EngineError): owner.run()

if __name__ == '__main__': unittest.main()
