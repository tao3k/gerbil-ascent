"""Caller-controlled counts on actual native Programs, not Python inference."""
import unittest
import os

from ascent import Engine, EngineError, FactLimits


SOURCE = '''
(define-evidence (make-evidence)
  (let (program (ascent
      (relation input ((value exact-integer?)))
      (relation output ((value exact-integer?)))
      ((output V) <-- (input V))))
    (gerbil-ascent-program (.ref program 'relations) (.ref program 'rules)
      (.ref program 'max-input-facts) (.ref program 'max-derived-facts)
      (.ref program 'max-output-facts) '(input)))
  (lambda (program result query scope)
    (hash ("status" "recorded-only") ("gap" "not a per-row proof"))))
(def (make-operator)
  (relational-op-compile (relational-op-source 'input 1 [])))
(def (echo-value value) value)
(def (evaluation-count rows)
  (let-values (((program output)
                (relational-op-compile (relational-op-source 'input 1 rows))))
    (length (relational-query-name (relational-solve (relational-admit program)) output))))
(def (change-count before added)
  (let-values (((old current delta)
                (relational-op-delta-change (relational-op-function 1 identity)
                  before added)))
    (list (length old) (length current) (length delta))))
'''


class FactLimitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = Engine(os.environ['ASCENT_ENGINE_LIBRARY']) if os.environ.get('ASCENT_ENGINE_BACKEND') == 'abi' else Engine()

    @classmethod
    def tearDownClass(cls): cls.engine.shutdown()

    def test_default_has_no_fact_ceiling_and_withdraws_large_source(self):
        with self.engine.evidence(SOURCE, 'make-evidence', trusted=True) as session:
            self.assertEqual(session.fact_limits,
                             dict.fromkeys(('input', 'derived', 'output'), 'unlimited'))
            self.assertTrue(session.run(queries=['output'])['complete'])
            session.replace({'input': [[n] for n in range(33000)]})
            result = session.run(queries=['output'])
            self.assertTrue(result['complete'])
            self.assertEqual(len(result['relations']['output']), 33000)
            session.replace({'input': [[8]]})
            self.assertEqual(session.run(queries=['output'])['relations']['output'], [[8]])

    def test_operator_default_and_native_program_constructor_are_unlimited(self):
        with self.engine.dsl(SOURCE, trusted=True) as owner:
            with owner.call('make-operator') as value:
                self.assertIn('value', value.receipt)

    def test_native_reference_and_positive_change_have_no_default_count_ceiling(self):
        from test_module_calls import decode
        with self.engine.dsl(SOURCE, trusted=True) as owner:
            with owner.call('evaluation-count', [[n] for n in range(5000)]) as value:
                self.assertEqual(decode(value.graph), 5000)
            with owner.call('change-count', [[n] for n in range(100)],
                            [[n] for n in range(100, 5000)]) as value:
                self.assertEqual(decode(value.graph), [100, 5000, 4900])

    def test_finite_limits_count_duplicates_and_leave_rejected_update_atomic(self):
        with self.engine.evidence(SOURCE, 'make-evidence', trusted=True,
                                  limits=FactLimits(input=3)) as session:
            self.assertTrue(session.run(queries=['output'])['complete'])
            session.replace({'input': [[1], [2]]})
            before = session.run(queries=['output'])
            with self.assertRaisesRegex(EngineError, 'scheme row bound|source fact budget'):
                session.replace({'input': [[7], [7], [7], [7]]})
            after = session.run(queries=['output'])
            self.assertEqual(before['relations'], after['relations'])
            self.assertEqual(before['sourceGeneration'], after['sourceGeneration'])

    def test_explicit_output_and_derived_ceilings_are_native_failures(self):
        for limits in (FactLimits(derived=1), FactLimits(output=3)):
            with self.engine.evidence(SOURCE, 'make-evidence', trusted=True, limits=limits) as session:
                self.assertTrue(session.run(queries=['output'])['complete'])
                with self.assertRaisesRegex(EngineError, 'fact budget exceeded'):
                    session.replace({'input': [[1], [2]]})
                    session.run(queries=['output'])

    def test_policy_cannot_loosen_explicit_dsl_bounds(self):
        source = SOURCE.replace('((output V) <-- (input V)))',
                                '((output V) <-- (input V)) (bounds 2 4 6))')
        with self.engine.evidence(source, 'make-evidence', trusted=True,
                                  limits=FactLimits(input=100)) as session:
            self.assertEqual(session.fact_limits['input'], 2)
            self.assertTrue(session.run(queries=['output'])['complete'])
            with self.assertRaisesRegex(EngineError, 'scheme row bound|source fact budget'):
                session.replace({'input': [[1], [2], [3]]})

    def test_invalid_finite_policy_is_rejected_natively(self):
        for value in (0, -1, True, 1.5, 'unlimited'):
            with self.assertRaises(EngineError):
                self.engine.evidence(SOURCE, 'make-evidence', trusted=True,
                                     limits=FactLimits(input=value))

    def test_pure_dsl_text_uses_unlimited_counts_but_respects_explicit_bounds(self):
        text = '(ascent (relation input ((value exact-integer?))))'
        with self.engine.open_sources(text, limits=FactLimits(input=5)) as session:
            self.assertEqual(session.fact_limits['input'], 5)
            self.assertEqual(session.fact_limits['output'], 'unlimited')
        with self.engine.open_sources(text + ' ') as session:
            self.assertEqual(session.fact_limits['input'], 'unlimited')

    def test_large_request_default_and_explicit_caller_byte_policy(self):
        from test_module_calls import decode
        data = 'x' * (1048576 + 1)
        with self.engine.dsl(SOURCE, trusted=True) as owner:
            with owner.call('echo-value', data) as value:
                self.assertEqual(decode(value.graph), data)
        with Engine(max_input_bytes=128) as limited:
            with self.assertRaisesRegex(EngineError, 'caller input byte bound'):
                limited.dsl('(def (echo x) x)' + ' ' * 256, trusted=True)
            # Rejection before VM entry must leave the shared VM usable.
            self.assertEqual(limited.describe()['abi'], 1)
            self.assertEqual(limited.max_input_bytes, 128)
        self.assertIsNone(self.engine.max_input_bytes)



if __name__ == '__main__': unittest.main()
