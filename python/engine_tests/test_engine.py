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
from ascent_engine import Engine, EngineError

ROOT=Path(__file__).parents[2]

class EngineLibrary(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine=Engine(os.environ.get('ASCENT_ENGINE_LIBRARY', ROOT/'.gerbil/lib/libascent.dylib'))
        cls.wire=json.loads(Path(os.environ['ASCENT_ENGINE_WIRE']).read_text())
        print('CFFI-RUNTIME-INITIALIZED',flush=True)
    @classmethod
    def tearDownClass(cls):
        cls.engine.shutdown()
        if cls.engine.lib.ascent_runtime_init() != -2: raise AssertionError('shutdown must be terminal')
        print('CFFI-RUNTIME-SHUTDOWN-OK',flush=True)

    def test_c_bytes_and_thread_errors_do_not_enter_scheme(self):
        ffi=self.engine.ffi; lib=self.engine.lib
        for data in (b'',b'{}\0',b'\xff',b'\xc0\x80',b'\xed\xa0\x80',b'\xf4\x90\x80\x80'):
            result=ffi.new('ascent_result *')
            self.assertEqual(lib.ascent_request(data,len(data),result),-4)
            lib.ascent_result_release(result)
            self.assertEqual(result.length,0);self.assertEqual(result.payload,ffi.NULL)
        duplicate=b'{"operation":"describe","operation":"close"}'
        result=ffi.new('ascent_result *')
        self.assertEqual(lib.ascent_request(duplicate,len(duplicate),result),-1)
        lib.ascent_result_release(result)
        statuses=[]
        def wrong_thread():
            result=ffi.new('ascent_result *');data=b'{"operation":"describe"}'
            statuses.append(lib.ascent_request(data,len(data),result));lib.ascent_result_release(result)
        thread=threading.Thread(target=wrong_thread);thread.start();thread.join()
        self.assertEqual(statuses,[-3])
        self.assertEqual(self.engine.request({'operation':'describe'})['abi'],1)

    def test_admission_unknown_fields_stale_handles_and_budget(self):
        for request in ({'operation':'describe','eval':'42'}, {'operation':'run','handle':-1}):
            with self.assertRaises(EngineError):self.engine.request(request)
        with self.engine.open(self.wire['finite:0']) as session:
            held=session.run();self.assertTrue(held['complete'])
            with self.assertRaises(EngineError):
                session.replace([{'relation':'cast','rows':[['a0','movie-left']]}])
            self.assertEqual(session.run(),held)
            with self.assertRaises(EngineError):
                session.replace([{'relation':'actor_answer','rows':[]}])
            with self.assertRaises(EngineError):
                session.replace([{'relation':'cast','rows':[]},
                                 {'relation':'blocked_actor','rows':[['movie-left']]}])
            self.assertEqual(session.run(),held)
            # A clean retained session returns its completed cached result even
            # with a zero budget; only an unevaluated session is incomplete.
            self.assertTrue(session.run(0)['complete'])
            self.assertTrue(session.run()['complete'])
        with self.assertRaises(EngineError):session.run()
        with self.engine.open(self.wire['finite:0']) as fresh:
            self.assertFalse(fresh.run(0)['complete'])
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
            session.replace([{'relation':'edge','rows':[['c','d']]},{'relation':'blocked','rows':[]}])
            updated=session.run()
            self.assertEqual(updated['relations'],{'path':[['c','d']],'safe':[['c','d']],'from_a':[]})
            self.assertEqual(result,held)

    def test_all_1536_quint_lean_observations_through_cffi(self):
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
                session.replace([{'relation':'cast','rows':[row for i,row in enumerate(casts) if bits&(1<<i)]},
                                 {'relation':'blocked_actor','rows':[[a] for i,a in enumerate(actors) if bits&(1<<(6+i))]}])
                result=session.run();self.assertTrue(result['complete']);rows=result['relations']
                evidence=[['left',*r] for r in rows['left_evidence']]+[['right',*r] for r in rows['right_evidence']]
                self.assertEqual([identity,mask(evidence,trace),mask(rows['actor_answer'],[[a] for a in actors]),
                                  mask(rows['cast_trace'],trace)],observation)
                if (identity+1)%64==0:print(f'CFFI-CAST {identity+1}/1536',flush=True)
        finally:
            for session in sessions.values():session.close()

if __name__=='__main__':unittest.main()
