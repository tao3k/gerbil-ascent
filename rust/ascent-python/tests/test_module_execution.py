"""Real Rust owners, operator graph lowering and independent replay factors."""
from contextlib import ExitStack
from pathlib import Path
import unittest
import os
import subprocess
import sys
import ascent

ROOT=Path(__file__).resolve().parents[3]
QUAL=':gerbil-ascent/t/qualification/evidence-api-module'
VIEW=':gerbil-ascent/core/relation-view'

def symbol(name): return {'type':'symbol','value':name}

def decode(graph):
    nodes={n['id']:n for n in graph['nodes']}
    def item(value):
        if 'ref' in value: value=nodes[value['ref']]
        kind=value['type']
        if kind=='null': return []
        if kind=='number': return int(value['value'])
        if kind in ('string','symbol','boolean'): return value['value']
        if kind=='vector': return [item(v) for v in value['items']]
        if kind=='pair': return [item(value['car']),*item(value['cdr'])]
        raise AssertionError(kind)
    return item(graph['root'])

SOLVE="""
(def (solve op)
  (let* ((fragment (relational-op-fragment op 'answer))
         (program (relational-compose (list fragment) 128 256 512))
         (solution (relational-solve (relational-admit program))))
    (relational-query solution fragment 'answer)))
"""

class ModuleExecution(unittest.TestCase):
    def setUp(self): self.engine=ascent.Engine(workers=4)
    def tearDown(self): self.engine.shutdown()

    def test_fixedpoint_join_union_finite_mapping_and_contextual_transformer_application(self):
        source=SOLVE+"""
(def (paths)
  (let (edge (relational-op-source 'edge 2 '((0 1) (1 2) (2 3))))
    (solve (relational-op-fix 2 (lambda (path)
      (relational-op-union edge
        (relational-op-project (relational-op-join path edge 1 0) '(0 3))))))))
(def (mapped)
  (solve (relational-op-flatmap (relational-op-source 'input 1 '((1) (2) (3)))
          1 '(((1) (4)) ((1) (5)) ((2) (5))))))
(def (selected)
  (solve (relational-op-select-eq (relational-op-source 'input 2 '((1 2) (3 4))) 0 3)))
(def (applications)
  (let ((f (relational-op-function 2 (lambda (input) (relational-op-project input '(1)))))
        (a (relational-op-source 'a 2 '((0 1))))
        (b (relational-op-source 'b 2 '((0 9)))))
    (solve (relational-op-union (relational-op-apply f a) (relational-op-apply f b)))))
"""
        with self.engine.dsl(source,trusted=True) as module:
            for name,wanted in [('paths',[[0,1],[0,2],[0,3],[1,2],[1,3],[2,3]]),
                                ('mapped',[[4],[5]]),('selected',[[3,4]]),('applications',[[1],[9]])]:
                with module.call(name) as result: self.assertEqual(decode(result.graph),wanted)

    def test_per_descriptor_cardinality_auxiliary_mapping_and_retained_rollback(self):
        source="""
(def (make) (relational-op-function 1 (lambda (input)
  (relational-op-flatmap input 1 '(((1) (4)) ((2) (5)))))))
(def (change old added cap) (relational-op-delta-change (make) old added cap))
(def (retain rows) (relational-op-open-retained (make) rows 16 64 128))
"""
        with self.engine.dsl(source,trusted=True) as module,ExitStack() as stack:
            with module.call('change',[[1]],[[1]],1) as value:
                self.assertEqual(decode(value.graph),[[[4]],[[4]],[]])
            with self.assertRaises(ascent.EngineError): module.call('change',[[1]],[[2]],1)
            retained=stack.enter_context(module.call('retain',[[1]]))
            with self.assertRaises(ascent.EngineError):
                module.call('relational-op-retained-replace!',retained.reference(),[[1,2]],module=':gerbil-ascent/program/interface')
            with module.call('relational-op-retained-rows',retained.reference(),module=':gerbil-ascent/program/interface') as value:
                self.assertEqual(decode(value.graph),[[4]])
            with module.call('relational-op-retained-replace!',retained.reference(),[[2]],module=':gerbil-ascent/program/interface'): pass
            with module.call('relational-op-retained-rows',retained.reference(),module=':gerbil-ascent/program/interface') as value:
                self.assertEqual(decode(value.graph),[[5]])

    def test_registered_module_closure_and_export_order_is_distinct_from_empty_selection(self):
        self.engine.register_module(QUAL,(ROOT/'t/qualification/evidence-api-module.ss').read_text(),trusted=True)
        with self.engine.module(QUAL) as owner:
            with owner.call('make-export-view',[[0,0],[1,1]],[[1,1],[0,0]]) as view:
                for args,wanted in [((),[[1,1],[0,0]]),(([],[]),[[0,0],[1,1]]),(([1,1],[1,0]),[])]:
                    with owner.call('gerbil-ascent-view-rows',view.reference(),*args,module=VIEW) as public:
                        self.assertEqual(decode(public.graph),wanted)
            with self.engine.open_module(QUAL,'make-operator',[[0,1],[1,2]]) as session:
                result=session.run(queries=['targets'])
                self.assertEqual(result['relations']['targets'],[[1],[2]])
                session.replace({'edge':[[7,8]]})
                self.assertEqual(session.run(queries=['targets'])['relations']['targets'],[[8]])

    def test_module_inventory_and_locations_reject_cycles_and_preserve_loaded_exports(self):
        self.engine.register_module(':consumer/a','(export answer) (def (answer) 1)',trusted=True)
        with self.engine.module(':consumer/a') as old:
            self.engine.register_module(':consumer/a','(export answer) (def (answer) 2)',trusted=True)
            with old.call('answer') as result: self.assertEqual(decode(result.graph),1)
            with self.engine.module(':consumer/a') as new:
                with new.call('answer') as result: self.assertEqual(decode(result.graph),2)
        self.engine.register_module(':consumer/a','(import :consumer/b) (export a) (def a 1)',trusted=True)
        self.engine.register_module(':consumer/b','(import :consumer/a) (export b) (def b 2)',trusted=True)
        with self.assertRaises(ascent.EngineError): self.engine.module(':consumer/a')
        with self.assertRaises(ascent.EngineError):
            self.engine.register_module(':gerbil-ascent/program/interface','(export fake)',trusted=True)

    def test_component_constructor_and_module_convenience_keep_independent_session(self):
        source=(ROOT/'rust/ascent/tests/fixtures/evidence-source.ss').read_text()
        manifest={'schema':'ascent.evidence-components.v1','components':[
            {'id':'entry','source':'entry.ss','exports':['make-evidence'],'dependencies':[]}]}
        with self.engine.evidence_components(manifest,{'entry.ss':source},'entry','make-evidence',[1,2],trusted=True) as session:
            self.assertEqual(session.run(queries=['output'])['relations']['output'],[[1],[2]])
        with self.engine.components(manifest,{'entry.ss':source},'entry',trusted=True) as module:
            session=module.evidence('make-evidence',[3])
        with session:
            self.assertEqual(session.run(queries=['output'])['relations']['output'],[[3]])

    def test_registered_module_and_operator_execution_need_no_downstream_tools(self):
        script="""
import ascent,sys
engine=ascent.Engine(workers=2)
engine.register_module(':consumer/example',sys.argv[1],trusted=True)
with engine.open_module(':consumer/example','make-operator',[[0,1]]) as session:
    receipt=session.run(queries=['targets'])
    assert receipt['relations']['targets']==[[1]]
    with session.result(receipt) as result:
        with result.provenance('targets') as proof: assert proof.verify()
engine.shutdown()
"""
        env=dict(os.environ,PATH='',CARGO='',RUSTC='',PYTHONDONTWRITEBYTECODE='1')
        completed=subprocess.run([sys.executable,'-c',script,(ROOT/'t/qualification/evidence-api-module.ss').read_text()],env=env,capture_output=True,text=True,timeout=10)
        self.assertEqual(completed.returncode,0,completed.stdout+completed.stderr)

    def test_stratified_proof_exposes_grounded_typed_factors_and_revokes_on_update(self):
        dsl='''(ascent (relation input ((x integer?))) (relation blocked ((x integer?)))
          (relation kept ((x integer?))) (relation total ((x integer?)))
          ((kept Y) <-- (input X) (not (blocked X)) (if (X) (even? X)) (let Y (X) (+ X 1)))
          ((total T) <-- (aggregate T gerbil-ascent-sum (Y) (kept Y))))'''
        with self.engine.open_sources(dsl) as session:
            session.run();session.replace({'input':[[0],[2],[3]],'blocked':[[2]]})
            receipt=session.run()
            with session.result(receipt) as result:
                with session.provenance(receipt,'total') as proof:
                    graph=proof.graph
                    self.assertEqual(graph['status'],'complete');self.assertEqual(graph['checkerVersion'],2)
                    kinds={w['kind'] for e in graph['edges'] for w in e['witnesses']}
                    self.assertEqual(kinds,{'absent','guard','compute','aggregate'})
                    self.assertTrue(proof.verify())
                    session.replace({'blocked':[[0]]})
                    with self.assertRaises(ValueError): _=proof.graph

if __name__=='__main__': unittest.main()
