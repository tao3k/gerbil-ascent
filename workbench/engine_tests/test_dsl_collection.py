"""Declaration order, hygienic rule expansion and explicit source/output bindings."""
import unittest
from ascent import Engine, EngineError
from test_module_calls import decode

COPY = '''(define-evidence (make) (sources input) (outputs output)
  (relation input ((x integer?)) ((1))) (relation output ((x integer?)))
  ((output X) <-- (input X)))'''

class DSLCollectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.engine = Engine()
    @classmethod
    def tearDownClass(cls): cls.engine.close()

    def test_include_effects_and_declaration_order(self):
        source = '''(def nested (ascent-fragment (relation nested (x) ((2)))))
          (define-evidence (make) (sources early late) (outputs early nested late)
            (relation early (x) ((1))) (include nested) (relation late (x) ((3))))'''
        with self.engine.evidence(source, trusted=True) as session:
            self.assertEqual([r['name'] for r in session.descriptors], ['early', 'nested', 'late'])
            self.assertEqual(session.run()['relations'], {'early': [[1]], 'nested': [[2]], 'late': [[3]]})
        with self.assertRaises(EngineError):
            self.engine.dsl('(def observed []) (def (note x) (set! observed x))', trusted=True)

    def test_macro_scope_default_storage_and_rule_order(self):
        source = '''(define-evidence (make) (sources input) (outputs output)
          (relation input ((x integer?)) ((1)))
          (macro copied ((target ident))
            (relation target ((x integer?))) ((target x) <-- (input x)))
          (copied middle) (relation output ((x integer?))) ((output x) <-- (middle x)))'''
        with self.engine.evidence(source, trusted=True) as session:
            self.assertEqual([r['name'] for r in session.descriptors], ['input', 'middle', 'output'])
            self.assertEqual(session.run()['relations']['output'], [[1]])
            session.replace({'input': [[7]]})
            self.assertEqual(session.run()['relations']['output'], [[7]])

    def test_hygienic_relation_and_rule_identifiers(self):
        source = '''(defrules scene () ((_ n) (ascent-fragment (relation n ((x integer?))))))
          (define-evidence (make) (sources input) (outputs output)
            (include (scene input)) (relation output ((x integer?)))
            ((output provider) <-- (input provider)))'''
        with self.engine.evidence(source, trusted=True) as session:
            self.assertEqual([r['name'] for r in session.descriptors], ['input', 'output'])
            session.replace({'input': [[3]]})
            self.assertEqual(session.run()['relations']['output'], [[3]])

    def test_empty_program_and_explicit_bounds(self):
        with self.engine.open_sources('(ascent (relation input (x)) (bounds 2 3 4))') as session:
            self.assertEqual(session.fact_limits, {'input': 2, 'derived': 3, 'output': 4})
        with self.engine.evidence('(define-evidence (empty) (sources) (outputs))', trusted=True) as empty:
            self.assertEqual(empty.run()['relations'], {})
        with self.assertRaises(EngineError): self.engine.open_sources('(ascent-fragment)')

    def test_malformed_declarations_still_rejected(self):
        for source in ('(ascent (bounds 0 2 3) (relation x (v)))',
                       '(ascent (relation x (v) [] (unknown 1)))'):
            with self.assertRaises(EngineError): self.engine.open_sources(source)
        with self.engine.open_sources('(ascent (bounds 1 2 3) (relation x (v)))') as session:
            self.assertEqual(session.fact_limits, {'input': 1, 'derived': 2, 'output': 3})

    def test_retained_callable_reads_mutable_export_and_keeps_scope_isolation(self):
        with self.engine.evidence(COPY, trusted=True) as owner:
            with self.engine.evidence(COPY.replace('((1))', '((99))'), trusted=True) as other:
                for value in (1, 7, 8):
                    before = owner.run()
                    result = owner.result(before)
                    owner.replace({'input': [[value]]})
                    with self.assertRaises(EngineError): result.rows('output')
                    self.assertEqual(owner.run()['relations']['output'], [[value]])
                    self.assertEqual(other.run()['relations']['output'], [[99]])
                    result.close()
                owner.replace({'input': []})
                self.assertEqual(owner.run()['relations']['output'], [])
                owner.replace({'input': [[11]]})
                self.assertEqual(owner.run()['relations']['output'], [[11]])
        with self.assertRaises(EngineError): owner.run()
        for source in ('(set! answer 11)', '(def (reader) (lambda () (answer)))'):
            with self.assertRaises(EngineError): self.engine.dsl(source, trusted=True)

    def test_public_typed_higher_order_dsl_without_downstream_import(self):
        with self.engine.transitive_graph() as close, self.engine.projection_graph(2, [1]) as project:
            with close.then(project) as function, self.engine.source_graph('edge', 2, [[0, 1], [1, 2]]) as input:
                with function.apply(input) as graph, graph.open_session('answer') as session:
                    self.assertEqual(session.run()['relations']['answer'], [[1], [2]])
                with self.engine.source_graph('wrong', 1, [[0]]) as wrong:
                    with self.assertRaises(ValueError): function.apply(wrong)

    def test_declarative_evidence_rules_sources_aliases_and_owned_explanation(self):
        source = '''(define-evidence (make-study) (sources input) (outputs (visible copied) count best)
          (relation input ((x integer?)))
          (macro copy ((target ident)) (relation target ((x integer?))) ((target x) <-- (input x)))
          (copy copied) (relation count (n)) (lattice best (key score) [] max)
          ((count n) <-- (aggregate n gerbil-ascent-count () (input x)))
          ((best (lit 'input) x) <-- (input x)))'''
        with self.engine.evidence(source, trusted=True) as session:
            self.assertEqual([r['name'] for r in session.descriptors if r['source']], ['input'])
            session.result(session.run(queries=[])).close()
            for values, maximum in (([2, 7], 7), ([2], 2), ([2, 7], 7)):
                session.replace({'input': [[v] for v in values]})
                with session.result(session.run()) as result:
                    self.assertEqual(decode(result.graph('visible')), [[v] for v in values])
                    self.assertEqual(decode(result.graph('count')), [[len(values)]])
                    self.assertEqual(decode(result.graph('best')), [['input', maximum]])
                    proof = result.explanation('visible')
                self.assertEqual(proof.graph['status'], 'recorded-only')
                self.assertIn('per-row proof', proof.graph['gap'])
                self.assertTrue(proof.current)
                proof.close()

    def test_declarative_evidence_binding_errors_do_not_infer_sources(self):
        for clauses in (
            '(sources input) (outputs absent) (relation input (x))',
            '(sources input input) (outputs input) (relation input (x))',
            '(sources input) (outputs (input other)) (relation input (x)) (relation other (x))',
            '(sources input) (relation input (x))',
            '(sources input) (outputs (answer input) (other input)) (relation input (x))'):
            with self.assertRaises(EngineError):
                self.engine.evidence('(define-evidence (make-study) ' + clauses + ')', trusted=True)
        source = '''(define-evidence (make-study) (sources) (outputs derived)
          (relation derived (x)) (fact (derived (lit 3))))'''
        with self.engine.evidence(source, trusted=True) as session:
            self.assertFalse(any(r['source'] for r in session.descriptors))
            self.assertEqual(session.run()['relations']['derived'], [[3]])
            with self.assertRaises(EngineError): session.replace({'derived': [[9]]})

if __name__ == '__main__': unittest.main()
