# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Actual CFFI proof-store admission and Scheme/Quint correspondence."""
import os
import subprocess
import sys
import unittest


class ComputationalEvidenceIntegration(unittest.TestCase):
    def test_native_store_through_selected_public_binding(self):
        code = '''
import copy, os
from ascent_engine import Engine, EngineError
from ascent_engine.evidence import ComputationalEvidence, compact_observation, expand_observation
from ascent_test_support.evidence_chain_study import shared_qualify, shared_tasks, shared_source, SHARED_CANDIDATE
library = os.environ.get('ASCENT_ENGINE_LIBRARY') if os.environ.get('ASCENT_ENGINE_BACKEND') == 'abi' else None
with Engine(library) as engine:
    checks = shared_qualify(engine)
    assert len(checks['taskChecks']) == 2 and len(checks['nativeQuintRows']) == 32
    with ComputationalEvidence(engine) as a, ComputationalEvidence(engine) as b:
        task = shared_tasks()[0]; source = shared_source(task)
        r = a.resolve(source, SHARED_CANDIDATE)
        changed = copy.deepcopy(source)
        changed['relations'][0][2].remove([1,2])
        assert a.fact(changed, SHARED_CANDIDATE, r['handle'], ['path',0,2])['status'] == 'unknown'
        assert b.fact(source, SHARED_CANDIDATE, r['handle'], ['path',0,2])['status'] == 'unknown'
        first = a.fragment(source, SHARED_CANDIDATE, r['handle'], ['path',0,2])
        first['nodes'].clear()
        assert a.fragment(source, SHARED_CANDIDATE, r['handle'], ['path',0,2])['nodes']
        observed = a.observe(source, SHARED_CANDIDATE, r['handle'], [['path',0,2]], support=True)
        assert observed['scope']['source-identity'] == source['identity']
        assert observed['observations'][0]['conclusion']['atom'] == ['path',0,2]
        assert expand_observation(compact_observation(observed)) == observed
        nodes = observed['supportNodes']
        assert nodes[-1]['atom'] == ['path',0,2] and nodes[-1]['parents']
        combined = a.observe(source, SHARED_CANDIDATE, r['handle'], [['path',0,2], ['path',0,1]], support=True)
        assert len({n['id'] for n in combined['supportNodes']}) == len(combined['supportNodes']) == len(nodes)
        stale = a.observe(changed, SHARED_CANDIDATE, r['handle'], [['path',0,2]], support=True)
        assert stale['observations'][0]['conclusion']['status'] == 'unknown'
        assert 'support' not in stale['observations'][0]
        assert expand_observation(compact_observation(stale)) == stale
        try:
            engine.request({'operation':'computational-evidence','action':'stats','owner':a.owner,'eval':'42'})
            raise AssertionError('extra request fields admitted')
        except EngineError: pass
        assert a.stats()['proof-builds'] == 1
    try: a.stats(); raise AssertionError('closed owner used')
    except ValueError: pass
print('COMPUTATIONAL-EVIDENCE-CFFI-OK', flush=True)
'''
        subprocess.run([sys.executable, '-u', '-'], input=code, text=True,
                       env=os.environ.copy(), check=True, timeout=45)


if __name__ == '__main__': unittest.main()
