"""Replay Quint expectations through the real Library, not a Python evaluator."""
from pathlib import Path
import json
import os
import unittest

from ascent_engine import Engine, EngineError, FactLimits
from test_native_module_calls import decode

FIXTURE = Path(__file__).resolve().parents[2] / 't/qualification/fixtures/native-evidence/conformance.json'
SOURCE = '''
(defrules copy-rule ()
  ((_ from to)
   (gerbil-ascent-rule
    (list (gerbil-ascent-atom to (list (gerbil-ascent-variable 'value))))
    (list (gerbil-ascent-atom from (list (gerbil-ascent-variable 'value)))))))
(define-evidence (make-evidence values)
 (gerbil-ascent-program
  (list (gerbil-ascent-relation 'input 1 (map list values))
        (gerbil-ascent-relation 'output 1 []))
  (list (copy-rule 'input 'output)) +inf.0 +inf.0 +inf.0 '(input))
 (lambda (program result query scope)
  (vector (hash-ref scope "sourceGeneration")
          (cdr (assq 'input (hash-ref scope "sources")))
          "recorded-only" "per-row-proof-unavailable" (.ref program 'rules))))
'''


def rows(mask):
    return [[value] for value in (0, 1) if mask & (1 << value)]


def mask_of(actual):
    if any(row not in [[0], [1]] for row in actual):
        raise AssertionError(actual)
    return sum(1 << row[0] for row in actual)


class NativeEvidenceConformance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        library = os.environ.get('ASCENT_ENGINE_LIBRARY') if os.environ.get('ASCENT_ENGINE_BACKEND') == 'abi' else None
        cls.engine = Engine(library)

    @classmethod
    def tearDownClass(cls):
        cls.engine.shutdown()

    def test_all_quint_trajectories(self):
        cases = json.loads(FIXTURE.read_text())
        self.assertEqual(len(cases), 50)
        self.assertEqual({case[0][0] for case in cases}, {0, 1})
        for case in cases:
            (limit, before, after), events, *expected = case
            with self.subTest(limit=limit, before=before, after=after, events=events):
                self.replay(limit, before, after, events, expected)

    def replay(self, limit, before, after, events, expected):
        session = self.engine.evidence(SOURCE, 'make-evidence', [r[0] for r in rows(before)],
                                      trusted=True, limits=FactLimits(input=limit or None))
        self.assertEqual(session.fact_limits['input'], limit or 'unlimited')
        result, proof = None, None
        generation, observed_source, proof_generation, proof_rows = 0, before, -1, 0

        def observation():
            alive = session.handle is not None
            result_live = False
            if alive and result is not None and result.handle is not None:
                try:
                    payload = result.rows('output')
                except EngineError as error:
                    self.assertIn('stale or unknown native result', str(error))
                else:
                    result_live = True
                    self.assertEqual(payload['sourceGeneration'], generation)
                    self.assertEqual(mask_of(decode(payload['value'])), observed_source)
            held = alive and proof is not None and proof.handle is not None
            native = False
            if held:
                # A live explanation is a distinct native entry, not a result.
                # A stale entry fails lookup before the kind check.
                try:
                    self.engine.request({'operation': 'native-result', 'handle': session.handle,
                                         'result': proof.handle, 'action': 'rows', 'relation': 'output'})
                except EngineError as error:
                    native = 'rows requires a result handle' in str(error)
                    if not native:
                        self.assertIn('stale or unknown native result', str(error))
                else:
                    self.fail('explanation was admitted as a result')
                # Historical copied observation remains readable, not CURRENT.
                root = proof.graph['root']
                nodes = {n['id']: n for n in proof.graph['nodes']}
                vector = nodes[root['ref']]
                source = decode({'root': vector['items'][1], 'nodes': proof.graph['nodes']})
                self.assertEqual(mask_of(source), proof_rows)
                self.assertEqual(proof.receipt['sourceGeneration'], proof_generation)
            return [int(alive), generation, observed_source, int(result_live), int(held),
                    int(native), proof_generation, proof_rows]

        try:
            self.assertEqual(observation(), expected[0])
            for index, event in enumerate(events):
                if event in (0, 7):
                    if result is not None: result.close()
                    receipt = session.run(queries=['output'])
                    self.assertTrue(receipt['complete'])
                    if event == 7: self.assertTrue(receipt['nativeResultReused'])
                    result = session.result(receipt)
                    generation = receipt['sourceGeneration']
                elif event == 1:
                    proof = result.explanation('output')
                    proof_generation = proof.receipt['sourceGeneration']
                    root = proof.graph['root']
                    vector = {n['id']: n for n in proof.graph['nodes']}[root['ref']]
                    proof_rows = mask_of(decode({'root': vector['items'][1], 'nodes': proof.graph['nodes']}))
                    self.assertIn('per-row-proof-unavailable', str(proof.graph))
                elif event == 2:
                    result.close()
                    with self.assertRaises(ValueError): result.rows('output')
                elif event == 3:
                    receipt = session.replace({'input': rows(after)})
                    self.assertTrue(receipt['updated'])
                    generation = receipt['sourceGeneration']
                    observed_source = after
                elif event == 4:
                    with self.assertRaises(EngineError):
                        session.replace([{'relation': 'input', 'rows': []},
                                         {'relation': 'output', 'rows': [[0]]}])
                elif event == 5:
                    proof.close()
                    with self.assertRaises(ValueError): proof.graph
                elif event == 6:
                    session.close()
                    with self.assertRaises(ValueError): session.run()
                else:
                    self.fail(f'unknown Quint event {event}')
                self.assertEqual(observation(), expected[index + 1])
        finally:
            if result is not None: result.close()
            if proof is not None: proof.close()
            session.close()

    def test_scope_isolation_foreign_reference_and_failed_load(self):
        with self.assertRaises(EngineError): self.engine.dsl('(unknown-dsl-form)', trusted=True)
        with self.engine.dsl('(def (make x) (lambda (y) (+ x y)))', trusted=True) as a:
            with self.engine.dsl('(def (make x) (lambda (y) (- x y)))', trusted=True) as b:
                value = a.call('make', 7)
                try:
                    with value.apply(2) as answer: self.assertEqual(decode(answer.graph), 9)
                    with b.call('make', 7) as other:
                        with other.apply(2) as answer: self.assertEqual(decode(answer.graph), 5)
                    with self.assertRaises(EngineError): b.call('make', value.reference())
                finally:
                    value.close()
                with self.assertRaises(ValueError): value.apply(2)
            with a.call('make', 3) as value:
                with value.apply(1) as answer: self.assertEqual(decode(answer.graph), 4)
        with self.assertRaises(ValueError): a.call('make', 1)


if __name__ == '__main__': unittest.main()
