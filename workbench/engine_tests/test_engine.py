# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Actual shared-library boundaries and frozen foreign observations; no oracle derivation."""
import json
import os
from pathlib import Path
import sys
import threading
import unittest
import copy
sys.path.insert(0,str(Path(__file__).parents[1]/'src'))
from ascent import Engine, EngineError
from ascent.evidence import rows_equal

ROOT=Path(__file__).parents[2]

class EngineLibrary(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine=Engine()
        from engine_fixture import finite_movie_program
        cls.wire={f'finite:{family}':finite_movie_program(cls.engine,family) for family in range(3)}
        print('CFFI-RUNTIME-INITIALIZED',flush=True)
    @classmethod
    def tearDownClass(cls):
        cls.engine.close()
        with cls().assertRaises((EngineError, ValueError)): cls.engine.describe()
        print('CFFI-RUNTIME-SHUTDOWN-OK',flush=True)

    def test_c_bytes_and_thread_errors_do_not_enter_scheme(self):
        for data in (b'', b'{}\0', b'\xff', b'\xc0\x80', b'\xed\xa0\x80', b'\xf4\x90\x80\x80'):
            with self.assertRaises((TypeError, ValueError, EngineError)):
                self.engine.dsl(data, trusted=True)
        with self.assertRaises(TypeError): self.engine.describe(eval='42')
        observations = []
        thread = threading.Thread(target=lambda: observations.append(self.engine.describe()['abi']))
        thread.start(); thread.join(timeout=5)
        self.assertFalse(thread.is_alive())
        self.assertEqual(observations, [1])
        self.assertEqual(self.engine.describe()['abi'], 1)

    def test_admission_unknown_fields_stale_handles_and_budget(self):
        with self.assertRaises(TypeError): self.engine.describe(eval='42')
        with self.engine.open(self.wire['finite:0']) as session:
            held=session.run();self.assertTrue(held['complete'])
            with self.assertRaises(EngineError):
                session.replace({'cast':[['a0','movie-left']]})
            self.assertEqual(session.run()['relations'],held['relations'])
            with self.assertRaises(EngineError):
                session.replace({'actor_answer':[]})
            with self.assertRaises(EngineError):
                session.replace({'cast':[], 'blocked_actor':[['movie-left']]})
            self.assertEqual(session.run()['relations'],held['relations'])
            # A clean retained session returns its completed cached result even
            # with a zero budget; only an unevaluated session is incomplete.
            with self.assertRaises(EngineError): session.run(0)
            self.assertTrue(session.run()['complete'])
        with self.assertRaises((EngineError, ValueError)):session.run()
        with self.engine.open(self.wire['finite:0']) as fresh:
            with self.assertRaises(EngineError): fresh.run(0)
            self.assertTrue(fresh.run()['complete'])

    def test_general_recursive_graph_negation_and_literal_updates(self):
        def relation(name,width,source,rows):
            return {'name':name,'columns':[{'kind':'symbol'} for _ in range(width)],'source':source,'rows':rows}
        def atom(name,*terms,negative=False):
            value={'relation':name,'terms':list(terms)}
            if negative:value['not']=True
            return value
        def rule(head,*body):return {'head':[head],'body':list(body)}
        x,y,z=({'var':n} for n in ('x','y','z'))
        program={'relations':[relation('edge',2,True,[['a','b'],['b','c']]),
                              relation('blocked',1,True,[['c']]),relation('path',2,False,[]),
                              relation('safe',2,False,[]),relation('from_a',1,False,[])],
                 'rules':[rule(atom('path',x,y),atom('edge',x,y)),
                          rule(atom('path',x,z),atom('path',x,y),atom('edge',y,z)),
                          rule(atom('safe',x,y),atom('path',x,y),atom('blocked',y,negative=True)),
                          rule(atom('from_a',y),atom('path',{'const':'a'},y))],
                 'queries':['path','safe','from_a']}
        with self.engine.open(program) as session:
            result=session.run();held=copy.deepcopy(result)
            self.assertTrue(result['complete'])
            self.assertCountEqual(result['relations']['path'],[['a','b'],['b','c'],['a','c']])
            self.assertEqual(result['relations']['safe'],[['a','b']])
            self.assertCountEqual(result['relations']['from_a'],[['b'],['c']])
            session.replace({'edge':[['c','d']], 'blocked':[]})
            updated=session.run()
            self.assertEqual(updated['relations'],{'path':[['c','d']],'safe':[['c','d']],'from_a':[]})
            self.assertEqual(result,held)

    def test_movie_contract_shape_repair_and_current_source_witnesses(self):
        from ascent_workbench import complex_movie_study as study
        from ascent_workbench.complex_movie_validation import singleton_heads
        source=json.loads(study.FIXTURE.read_text());case=study.cases()[0]
        views=study.materialize(self.engine,source)
        valid=study.gold(case,True);malformed=copy.deepcopy(valid)
        malformed['rules'][0]['head']=malformed['rules'][0]['head'][0]
        with self.assertRaises((TypeError,ValueError)):
            study.program(source,malformed,views)
        repaired,count=singleton_heads(malformed)
        self.assertEqual(count,1);self.assertEqual(repaired,valid)
        actual=study.case_program(self.engine,source,case,repaired,views)
        self.assertTrue(rows_equal(actual, [['Q123351'],['Q208026'],['Q202589']]))
        changed={**case,'withdrawal':['Q25188','Q123351']};current=study.source_for(source,changed)
        fresh_views=study.materialize(self.engine,current)
        correct=study.case_program(self.engine,current,changed,repaired,fresh_views)
        stale=study.case_program(self.engine,current,changed,repaired,views)
        self.assertTrue(rows_equal(correct, [['Q208026'],['Q202589']]))
        self.assertFalse(rows_equal(stale, correct))
        union={**case,'combine':'any','scope':'both'}
        mistaken={**union,'combine':'all'}
        union_answer=study.case_program(self.engine,source,union,study.gold(union,True),views)
        join_answer=study.case_program(self.engine,source,union,study.gold(mistaken,True),views)
        self.assertEqual(len(union_answer),154);self.assertEqual(len(join_answer),3)
        self.assertFalse(rows_equal(union_answer, join_answer))
        scoped,qualified,withdrawal=study.cases('country-qualified')
        single=study.case_program(self.engine,source,qualified,study.gold(qualified,True),views)
        self.assertEqual(single,[['Q208026']])
        selective=study.case_program(self.engine,source,scoped,study.gold(scoped,True),views)
        self.assertEqual(len(selective),89);self.assertIn(['Q208026'],selective)
        current=study.source_for(source,withdrawal);updated_views=study.materialize(self.engine,current)
        changed=study.case_program(self.engine,current,withdrawal,study.gold(withdrawal,True),updated_views)
        self.assertEqual(len(changed),88);self.assertNotIn(['Q208026'],changed)
        # Fusing the two branch film variables in the direct answer rule loses Hardy.
        a,f,d,e=map(study.var,('a','f','d','e'))
        fused={'relations':[],'rules':[study.rule(study.atom('answer',a),
            study.atom('eligible',study.const('Q145'),f,d,a),
            study.atom('omitted_film',f,negative=True),
            study.atom('eligible',study.const('Q96'),f,e,a),
            study.atom('coactor',study.const('Q38111'),f,a))]}
        self.assertEqual(study.case_program(self.engine,source,qualified,fused,views),[])

    def test_all_1536_quint_lean_observations_through_rust(self):
        corpus=json.loads((ROOT/'t/qualification/fixtures/movie-cast/conformance.json').read_text())
        actors=['a0','a1','a2'];casts=[[film,a] for film in ('movie-left','movie-right') for a in actors]
        trace=[[scope,film,a] for scope,film in (('left','movie-left'),('right','movie-right')) for a in actors]
        sessions={}
        def mask(rows, choices): return sum(1<<i for i,row in enumerate(choices) if row in rows)
        try:
            self.assertEqual(len(corpus),1536)
            for observation in corpus:
                identity=observation[0];family,bits=divmod(identity,512)
                if family not in sessions:
                    sessions[family]=self.engine.open(self.wire[f'finite:{family}'])
                    self.assertTrue(sessions[family].run()['complete'])
                session=sessions[family]
                session.replace({'cast':[row for i,row in enumerate(casts) if bits&(1<<i)],
                                 'blocked_actor':[[a] for i,a in enumerate(actors) if bits&(1<<(6+i))]})
                result=session.run();self.assertTrue(result['complete']);rows=result['relations']
                evidence=[['left',*r] for r in rows['left_evidence']]+[['right',*r] for r in rows['right_evidence']]
                self.assertEqual([identity,mask(evidence,trace),mask(rows['actor_answer'],[[a] for a in actors]),
                                  mask(rows['cast_trace'],trace)],observation)
                if (identity+1)%64==0:print(f'CFFI-CAST {identity+1}/1536',flush=True)
        finally:
            for session in sessions.values():session.close()

if __name__=='__main__':unittest.main()
