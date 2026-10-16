"""Replay all existing Quint lifecycle trajectories through installed Rust owners."""
from pathlib import Path
import json
import unittest
from ascent import Engine, EngineError, FactLimits

FIXTURE = Path(__file__).resolve().parents[2] / 't/qualification/fixtures/native-evidence/conformance.json'
SOURCE = '''(define-evidence (make-evidence) (sources input) (outputs output)
  (relation input ((value exact-integer?)) INITIAL)
  (relation output ((value exact-integer?))) ((output X) <-- (input X)))'''

def rows(mask): return [[value] for value in (0, 1) if mask & (1 << value)]
def definition(mask): return SOURCE.replace('INITIAL', '(' + ' '.join(f'({r[0]})' for r in rows(mask)) + ')')
def mask_of(actual):
    if any(row not in [[0], [1]] for row in actual): raise AssertionError(actual)
    return sum(1 << row[0] for row in actual)

class EvidenceConformance(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.engine = Engine()
    @classmethod
    def tearDownClass(cls): cls.engine.close()

    def test_all_quint_trajectories(self):
        cases = json.loads(FIXTURE.read_text())
        self.assertEqual(len(cases), 50)
        self.assertEqual({case[0][0] for case in cases}, {0, 1})
        for case in cases:
            (limit, before, after), events, *expected = case
            with self.subTest(limit=limit, before=before, after=after, events=events):
                self.replay(limit, before, after, events, expected)

    def replay(self, limit, before, after, events, expected):
        session = self.engine.evidence(definition(before), trusted=True, limits=FactLimits(input=limit or None))
        self.assertEqual(session.fact_limits['input'], limit or 'unlimited')
        result, proof = None, None
        generation, observed_source, proof_generation, proof_rows = 0, before, -1, 0

        def observation():
            alive = not session.closed
            result_live = False
            if alive and result is not None and not result.closed:
                try: actual = result.rows('output')['rows']
                except ValueError as error: self.assertRegex(str(error), 'closed|released')
                else:
                    result_live = True
                    self.assertEqual(result.source_generation, generation)
                    self.assertEqual(mask_of(actual), observed_source)
            held = alive and proof is not None and not proof.closed
            current = False
            if held:
                with self.assertRaises(TypeError): session.result(proof)
                current = proof.current
                data = proof.graph
                self.assertEqual(data['status'], 'recorded-only')
                actual = next(r['rows'] for r in data['sources'] if r['name'] == 'input')
                self.assertEqual(mask_of(actual), proof_rows)
                self.assertEqual(proof.source_generation, proof_generation)
            return [int(alive), generation, observed_source, int(result_live), int(held),
                    int(current), proof_generation, proof_rows]

        try:
            self.assertEqual(observation(), expected[0])
            for index, event in enumerate(events):
                if event in (0, 7):
                    if result is not None: result.close()
                    receipt = session.run()
                    self.assertTrue(receipt['complete'])
                    if event == 7: self.assertTrue(receipt['nativeResultReused'])
                    result = session.result(receipt)
                    generation = receipt['sourceGeneration']
                elif event == 1:
                    proof = result.explanation('output')
                    proof_generation = proof.source_generation
                    proof_rows = mask_of(next(r['rows'] for r in proof.graph['sources'] if r['name'] == 'input'))
                elif event == 2:
                    result.close()
                    with self.assertRaises(ValueError): result.rows('output')
                elif event == 3:
                    receipt = session.replace({'input': rows(after)})
                    self.assertTrue(receipt['updated'])
                    generation = receipt['sourceGeneration']
                    observed_source = after
                elif event == 4:
                    with self.assertRaises(EngineError): session.replace({'input': [], 'output': [[0]]})
                elif event == 5:
                    proof.close()
                    with self.assertRaises(ValueError): _ = proof.graph
                elif event == 6:
                    session.close()
                    with self.assertRaises(ValueError): session.run()
                else: self.fail(f'unknown Quint event {event}')
                self.assertEqual(observation(), expected[index + 1])
                print(f'EVIDENCE-CONFORMANCE-CHECK limit={limit} before={before} after={after} step={index + 1}', flush=True)
        finally:
            if result is not None: result.close()
            if proof is not None: proof.close()
            session.close()

    def test_definition_reuse_keeps_sessions_and_limits_independent(self):
        source = definition(1).replace('make-evidence', 'make-a') + definition(2).replace('make-evidence', 'make-b')
        manifest = {'schema': 'ascent.evidence-components.v1', 'components': [
            {'id': 'entry', 'source': 'entry.ss', 'exports': ['make-a', 'make-b'], 'dependencies': []}]}
        with self.engine.components(manifest, {'entry.ss': source}, 'entry', trusted=True) as factory:
            with factory.call('make-a') as declaration: a = declaration.open_session(limits=FactLimits(input=1))
            with factory.call('make-b') as declaration: b = declaration.open_session()
            with self.assertRaises(EngineError): factory.call('make-c')
            self.assertEqual(a.run()['relations']['output'], [[0]])
            a.replace({'input': []})
            self.assertEqual(b.run()['relations']['output'], [[1]])
        try:
            self.assertEqual(a.run()['relations']['output'], [])
            with self.assertRaises(ValueError): factory.call('make-a')
        finally: a.close(); b.close()

    def test_scope_isolation_foreign_reference_and_failed_load(self):
        with self.assertRaises(EngineError): self.engine.dsl('(unknown-dsl-form)', trusted=True)
        with self.engine.evidence(definition(1), trusted=True) as a, self.engine.evidence(definition(2), trusted=True) as b:
            receipt = a.run()
            result = a.result(receipt)
            value = result.reference('output', 0, 0)
            with self.assertRaises(EngineError): b.replace({'input': [[value]]})
            self.assertEqual(b.run()['relations']['output'], [[1]])
            result.close()
            with self.assertRaises(EngineError): value.scalar()
            self.assertEqual(a.run()['relations']['output'], [[0]])
        with self.assertRaises(EngineError): a.run()

if __name__ == '__main__': unittest.main()
