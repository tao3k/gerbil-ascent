"""Caller-owned native count and ABI byte policies; default ceilings are absent."""
import unittest
from ascent import Engine, EngineError, FactLimits

SOURCE = '''(define-evidence (make-evidence) (sources input) (outputs output)
  (relation input ((value exact-integer?)))
  (relation output ((value exact-integer?))) ((output V) <-- (input V)))'''

class FactLimitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.engine = Engine()
    @classmethod
    def tearDownClass(cls): cls.engine.close()

    def test_default_has_no_fact_ceiling_and_withdraws_large_source(self):
        with self.engine.evidence(SOURCE, trusted=True) as session:
            self.assertEqual(session.fact_limits, dict.fromkeys(('input', 'derived', 'output'), 'unlimited'))
            session.replace({'input': [[n] for n in range(33000)]})
            result = session.run()
            self.assertTrue(result['complete'])
            self.assertEqual(len(result['relations']['output']), 33000)
            session.result(result).close()
            session.replace({'input': [[8]]})
            self.assertEqual(session.run()['relations']['output'], [[8]])

    def test_operator_default_and_native_program_constructor_are_unlimited(self):
        graph = {'algorithm': 'projection', 'source': 'input', 'width': 1,
                 'rows': [[n] for n in range(5000)], 'output': 'answer', 'captures': {'columns': [0]}}
        with self.engine.core_graph(graph, trusted=True) as session:
            result = session.run(result_format='typed-rows').value()
            self.assertTrue(result['complete'])
            self.assertEqual(len(result['relations']['answer']), 5000)

    def test_native_reference_and_positive_change_have_no_default_count_ceiling(self):
        with self.engine.evidence(SOURCE, trusted=True) as session:
            session.replace({'input': [[n] for n in range(5000)]})
            with session.result(session.run()) as result:
                self.assertEqual(len(result.rows('output')['rows']), 5000)
                self.assertEqual(result.reference('output', 4999, 0).scalar(), 4999)
        change = '''(define-evidence (change) (sources previous current) (outputs previous current added)
          (relation previous ((x integer?))) (relation current ((x integer?)))
          (relation added ((x integer?))) ((added X) <-- (current X) (not (previous X))))'''
        with self.engine.evidence(change, trusted=True) as session:
            session.replace({'previous': [[n] for n in range(100)],
                             'current': [[n] for n in range(5000)]})
            rows = session.run()['relations']
            self.assertEqual([len(rows[n]) for n in ('previous', 'current', 'added')], [100, 5000, 4900])

    def test_finite_limits_count_duplicates_and_leave_rejected_update_atomic(self):
        with self.engine.evidence(SOURCE, trusted=True, limits=FactLimits(input=3)) as session:
            session.replace({'input': [[1], [2]]})
            before = session.run()
            with self.assertRaisesRegex(EngineError, 'fact budget'):
                session.replace({'input': [[7], [7], [7], [7]]})
            after = session.run()
            self.assertEqual(before['relations'], after['relations'])
            self.assertEqual(before['sourceGeneration'], after['sourceGeneration'])

    def test_explicit_output_and_derived_ceilings_are_native_failures(self):
        for limits in (FactLimits(derived=1), FactLimits(output=1)):
            with self.engine.evidence(SOURCE, trusted=True, limits=limits) as session:
                first = session.run()
                with self.assertRaisesRegex(EngineError, 'fact budget'):
                    session.replace({'input': [[1], [2]]})
                self.assertEqual(session.run()['sourceGeneration'], first['sourceGeneration'])

    def test_policy_cannot_loosen_explicit_dsl_bounds(self):
        bounded = SOURCE.replace('((output V) <-- (input V)))', '((output V) <-- (input V)) (bounds 2 4 6))')
        with self.engine.evidence(bounded, trusted=True, limits=FactLimits(input=100)) as session:
            self.assertEqual(session.fact_limits['input'], 2)
            with self.assertRaisesRegex(EngineError, 'fact budget'):
                session.replace({'input': [[1], [2], [3]]})

    def test_invalid_finite_policy_is_rejected_natively(self):
        for value in (0, -1, True, 1.5, 'unlimited'):
            with self.assertRaises((ValueError, TypeError, OverflowError)): FactLimits(input=value)

    def test_pure_dsl_text_uses_unlimited_counts_but_respects_explicit_bounds(self):
        text = '(ascent (relation input ((value exact-integer?))))'
        with self.engine.open_sources(text, limits=FactLimits(input=5)) as session:
            self.assertEqual(session.fact_limits['input'], 5)
            self.assertEqual(session.fact_limits['output'], 'unlimited')
        with self.engine.open_sources(text) as session:
            self.assertEqual(session.fact_limits['input'], 'unlimited')

    def test_large_request_default_and_explicit_caller_byte_policy(self):
        text = SOURCE.replace('exact-integer?', 'string?')
        data = 'x' * (1048576 + 1)
        with self.engine.evidence(text, trusted=True) as session:
            session.replace({'input': [[data]]})
            self.assertEqual(session.run()['relations']['output'], [[data]])
        with Engine(max_request_bytes=2048) as limited:
            with self.assertRaisesRegex(EngineError, 'caller request byte bound'):
                limited.dsl(text + ' ' * 2048, trusted=True)
            with limited.evidence(text, trusted=True) as session:
                with self.assertRaisesRegex(EngineError, 'caller request byte bound'):
                    session.replace({'input': [[data]]})
                session.replace({'input': [['ok']]})
                self.assertEqual(session.run()['relations']['output'], [['ok']])
            self.assertEqual(limited.describe()['abi'], 1)
            self.assertEqual(limited.max_request_bytes, 2048)
        self.assertIsNone(self.engine.max_request_bytes)

if __name__ == '__main__': unittest.main()
