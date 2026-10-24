"""Native constructors and real numeric values; no Python evaluator or checker."""
from pathlib import Path
import math
import unittest
import ascent

ROOT=Path(__file__).resolve().parents[3]
QUAL=':gerbil-ascent/t/qualification/evidence-api-module'

def numbers(graph):
    nodes={n['id']:n for n in graph['nodes']}
    def walk(item):
        if 'ref' in item: item=nodes[item['ref']]
        if item['type']=='number': return [item['value']]
        if item['type']=='pair': return walk(item['car'])+walk(item['cdr'])
        if item['type']=='vector': return [v for child in item['items'] for v in walk(child)]
        return []
    return walk(graph['root'])

class AggregatesExecution(unittest.TestCase):
    def setUp(self):
        self.engine=ascent.Engine(workers=4)
        self.engine.register_module(QUAL,(ROOT/'t/qualification/evidence-api-module.ss').read_text(),trusted=True)
    def tearDown(self): self.engine.shutdown()

    def test_original_mean_constructor_roundtrip_withdrawal_and_proof(self):
        with self.engine.open_module(QUAL,'make-aggregate',[1,2,4]) as session:
            first=session.run(queries=['average'])
            with session.result(first) as result:
                self.assertAlmostEqual(float(numbers(result.rows('average')['value'])[0]),7/3)
                with result.provenance('average') as proof:
                    self.assertTrue(proof.verify())
                    self.assertIn('mean',[w['operator'] for e in proof.graph['edges'] for w in e['witnesses'] if w['kind']=='aggregate'])
                    with self.engine.dsl('(def (inc x) (+ x 1))',trusted=True) as module:
                        with module.call('inc',result.reference('average',0,0)) as value:
                            self.assertAlmostEqual(float(numbers(value.graph)[0]),10/3)
                    with self.assertRaises(ascent.EngineError): session.replace({'number':[['not numeric']]})
                    self.assertTrue(proof.verify())
                    session.replace({'number':[]})
                    with self.assertRaises(ValueError): _=proof.graph
            self.assertEqual(session.run(queries=['average'])['relations']['average'],[])

    def test_mean_exact_to_inexact_overflow_and_direct_shape_validation(self):
        with self.engine.open_module(QUAL,'make-aggregate',[2**1100]) as session:
            with session.result(session.run()) as result:
                self.assertEqual(numbers(result.rows('average')['value']),['+inf.0'])
                with result.explanation('average') as observation:
                    self.assertIn('dependencies',str(observation.graph))
        with self.engine.module(':gerbil-ascent/program/aggregators') as module:
            with self.assertRaisesRegex(ascent.EngineError,'tuple arity'):
                module.call('gerbil-ascent-sum',[['not numeric'],[1,2]])
            with module.call('gerbil-ascent-count',[[],[],[]]) as value:
                self.assertEqual(numbers(value.graph),['3'])
            with module.call('gerbil-ascent-sum',[[0],[-0.0]]) as value:
                self.assertEqual(math.copysign(1.0,float(numbers(value.graph)[0])),-1.0)

    def test_native_dsl_initial_expression_frozen_complex_rows_and_no_implicit_authority(self):
        source='''(def (make values) (ascent (relation input (v) (map list values))
                    (relation out (v)) ((out V) <-- (input V))))'''
        with self.engine.rules(source,'make',[{'type':'vector','value':[1,2]},{'type':'vector','value':[1,2]}],trusted=True) as session:
            result=session.run();self.assertEqual(len(result['relations']['out']),1)
            with self.assertRaises(ascent.EngineError): session.replace({'input':[]})

if __name__=='__main__': unittest.main()
