"""Python-only consumers of full host-authorized native Scheme modules."""
import unittest

from ascent_engine import Engine, EngineError
from test_native_module_calls import decode


SOURCE = '''
  (defrules copy-rule ()
    ((_ from to)
     (gerbil-ascent-rule
       (list (gerbil-ascent-atom to (list (gerbil-ascent-variable 'value))))
       (list (gerbil-ascent-atom from (list (gerbil-ascent-variable 'value)))))))
  (def (make-closure n) (lambda (x) (+ n x)))
  (def (native-values . items) (apply values items))
  (def (make-cycle) (let (v (make-vector 1)) (vector-set! v 0 v) v))
  (define-evidence (make-evidence values)
    (gerbil-ascent-program
      (list (gerbil-ascent-relation 'input 1 (map list values))
            (gerbil-ascent-relation 'output 1 []))
      (list (copy-rule 'input 'output)) 32 64 96 '(input))
    (lambda (program result query scope)
      (hash ("status" "recorded-only") ("scope" scope)
            ("dependencies" (.ref program 'rules)) ("gap" "not a per-row proof"))))
'''


class NativeModuleSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.engine = Engine()

    @classmethod
    def tearDownClass(cls): cls.engine.shutdown()

    def test_authorization_required_by_python_and_native(self):
        with self.assertRaisesRegex(ValueError, 'explicitly authorized'):
            self.engine.dsl(SOURCE)
        with self.assertRaises(EngineError):
            self.engine.request({'operation': 'dsl-open', 'source': SOURCE, 'trusted': False})

    def test_macro_import_constructor_update_withdrawal_and_explanation(self):
        with self.engine.evidence(SOURCE, 'make-evidence',
                                            [1, 2], trusted=True) as session:
            with session.result(session.run(queries=['output'])) as result:
                self.assertEqual(sorted(decode(result.rows('output')['value'])), [[1], [2]])
                proof = result.explanation('output')
            self.assertIn('not a per-row proof', str(proof.graph))
            proof.close()
            session.replace({'input': [[8]]})
            with session.result(session.run(queries=['output'])) as result:
                self.assertEqual(decode(result.rows('output')['value']), [[8]])
            session.replace({'input': []})
            with session.result(session.run(queries=['output'])) as result:
                self.assertEqual(decode(result.rows('output')['value']), [])
        with self.assertRaises(ValueError): session.run()

    def test_closures_cycles_foreign_and_released_values(self):
        with self.engine.dsl(SOURCE, trusted=True) as owner:
            with owner.call('make-closure', 7) as function:
                with function.apply(5) as value:
                    self.assertEqual(decode(value.graph), 12)
                with owner.call('make-cycle') as cycle:
                    node = cycle.graph['nodes'][0]
                    self.assertEqual(node['items'], [{'ref': node['id']}])
                    reference = cycle.reference()
                with self.assertRaises(EngineError): owner.call('make-closure', reference)
            with self.assertRaises(ValueError): function.apply(5)
        with self.assertRaises(ValueError): owner.call('make-cycle')

    def test_isolated_module_names_and_export_boundaries(self):
        source = '(def (answer) VALUE)'
        with self.engine.dsl(source.replace('VALUE', '1'), trusted=True) as a:
            with self.engine.dsl(source.replace('VALUE', '2'), trusted=True) as b:
                with a.call('answer') as value: self.assertEqual(decode(value.graph), 1)
                with b.call('answer') as value: self.assertEqual(decode(value.graph), 2)
                with self.assertRaises(EngineError): a.call('identity', 1)
            with a.call('answer') as value: self.assertEqual(decode(value.graph), 1)

    def test_invalid_source_and_failed_load_do_not_create_usable_owner(self):
        for source in ['(import :gerbil/core)', '(module scene (import :gerbil/core))',
                       '(export make-evidence)', '(unknown-dsl-form)']:
            with self.assertRaises(EngineError):
                self.engine.dsl(source, trusted=True)

    def test_consumer_definitions_have_no_scheme_import_module_or_build(self):
        for token in ['(import', '(module', '(export', 'gxc', 'gerbil.pkg']:
            self.assertNotIn(token, SOURCE)
        with self.engine.dsl(SOURCE, trusted=True) as owner:
            with owner.call('native-values', 3, 5) as value:
                self.assertEqual(value.receipt['valueCount'], 2)
                self.assertEqual(decode(value.graph), [3, 5])


if __name__ == '__main__': unittest.main()
