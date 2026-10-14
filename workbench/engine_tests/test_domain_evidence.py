# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import os
import subprocess
import sys
import unittest


class DomainEvidenceIntegration(unittest.TestCase):
    def test_exact_domain_constraints_retention_and_invalidation(self):
        code = '''
import os
from ascent_engine import Engine,EngineError
from ascent_engine.domain_evidence import DomainEvidence
engine=Engine(os.environ.get('ASCENT_ENGINE_LIBRARY', '.gerbil/lib/libascent.dylib'))
memory=DomainEvidence(engine,'source-A')
bad=memory.observe('graph-schedule',[['g',[1,3,7,9],[1,3],[3,1]]],'trace-g')
assert bad['failedClaims'] and bad['currentChecks'][0]['requiredOrder']==[1,3]
update=memory.observe('graph-update',[['u',2,1,5,2,3]],'trace-u')
assert len(update['checkedDomainEvidence'])==2
assert update['currentChecks'][0]['claims']==[['update-read-version',False],['path-count-conservation',True],['path-count-nonnegative',True]]
series=memory.observe('series-precision',[['reciprocal',[1,1],-1,[3,1],[2,1],[3,1],False],['boundary',[4,1],2,[2,1],[0,1],[0,1],False]],'trace-series')
assert series['currentChecks'][0]['requiredInternalPrecision']==[4,1]
assert series['currentChecks'][0]['shouldInclude'] is True
assert series['currentChecks'][1]['shouldInclude'] is False
assert len(series['checkedDomainEvidence'])==3
memory.summary()
assert memory.journal[-1]['reusedComponents']
old=series['resultReference']; memory.replace_snapshot('source-B')
assert memory.summary()['checkedDomainEvidence']==[]
assert len(memory.summary()['domainContracts'])==3
assert not memory.summary()['failedClaims']
good=memory.observe('graph-schedule',[['g',[1,3,7,9],[1,3],[1,3]]],'trace-fixed')
assert not good['failedClaims'] and len(good['checkedDomainEvidence'])==1
try: memory.chain.answer(old,'Failed'); raise AssertionError('stale evidence accepted')
except ValueError: pass
try: engine.request({'operation':'domain-check','kind':'series-precision','observations':[['bad',[1,0],2,[3,1],[2,1],[0,1],True]]}); raise AssertionError('bad denominator accepted')
except EngineError: pass
memory.close()
class ChangedChecker:
 def __getattr__(self,name):return getattr(engine,name)
 def request(self,request):
  response=engine.request(request)
  if request.get('operation')=='domain-check':response['checkerVersion']='domain-evidence-v2-test'
  return response
memory=DomainEvidence(engine,'source-A')
memory.observe('graph-schedule',[['g',[1],[1],[1]]],'before-upgrade')
memory.engine=ChangedChecker()
upgraded=memory.observe('graph-update',[['u',1,1,3,1,2]],'after-upgrade')
assert len(upgraded['checkedDomainEvidence'])==1
assert len(upgraded['domainContracts'])==1
assert upgraded['domainContracts'][0]['checkerVersion']=='domain-evidence-v2-test'
memory.close()
print('DOMAIN-EVIDENCE-RETENTION-INVALIDATION-OK',flush=True)
'''
        subprocess.run([sys.executable, '-u', '-'], input=code, text=True, check=True,
                       env={**os.environ, 'PYTHONPATH': 'workbench/src:python/src'})
