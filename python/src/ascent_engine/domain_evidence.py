# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Snapshot-qualified exact domain checks and their Scheme relational memory.

The host supplies observed values. Scheme checks arithmetic/schedule contracts;
neither binding nor checker attests that arbitrary callers observed real code.
"""
import copy
import time
from .derivations import EvidenceChain
from .evidence import identity


class DomainEvidence:
    def __init__(self, engine, snapshot, retain=True):
        self.engine = engine; self.snapshot = snapshot; self.retain = retain
        self.observations = {}; self.chain = None; self.journal = []
        self.laws = {}
        self.checker_version = None

    def replace_snapshot(self, snapshot):
        if snapshot == self.snapshot: return
        if self.chain: self.chain.close()
        self.snapshot = snapshot; self.observations.clear(); self.chain = None
        if self.laws:self.chain=EvidenceChain(self.engine,self._sources(),self.retain)

    def observe(self, kind, observations, observation_receipt):
        if not isinstance(observation_receipt, str) or not observation_receipt:
            raise ValueError('an observation receipt identity is required')
        ids = [r[0] for r in observations]
        if not ids or len(set(ids)) != len(ids): raise ValueError('unique nonempty observation IDs required')
        began=time.monotonic()
        response = self.engine.request({'operation': 'domain-check', 'kind': kind, 'observations': observations})
        checker_seconds=time.monotonic()-began
        if self.checker_version is not None and response['checkerVersion'] != self.checker_version:
            if self.chain:self.chain.close()
            self.chain=None;self.observations.clear();self.laws.clear()
        self.checker_version=response['checkerVersion']
        if not self.retain: self.laws.clear()
        law = {'kind': kind, 'checkerVersion': response['checkerVersion'], 'contract': response['contract']}
        self.laws[identity(law)] = law
        key = identity({'snapshot': self.snapshot, 'receipt': observation_receipt,
                        'checker': response['checkerVersion'], 'kind': kind, 'observations': observations})
        if not self.retain: self.observations.clear()
        self.observations[key] = {'receipt': observation_receipt, 'kind': kind, 'checks': response['checks']}
        sources = self._sources()
        if self.chain: self.chain.replace(sources)
        else: self.chain = EvidenceChain(self.engine, sources, self.retain)
        result = self.summary()
        result['currentChecks'] = response['checks']
        result['observationIdentity'] = key
        result['checkerSeconds'] = checker_seconds
        return result

    def _sources(self):
        claims = []
        for key, observation in sorted(self.observations.items()):
            for check in observation['checks']:
                for name, passed in check['claims']:
                    claim = identity([key, check['id'], name])
                    claims.append([claim, passed])
        return [{'name': 'Snapshot', 'source': True, 'columns': [{'kind': 'symbol'}], 'rows': [[self.snapshot]]},
                {'name': 'ObservedClaim', 'source': True, 'columns': [{'kind': 'symbol'}, {'kind': 'boolean'}], 'rows': claims},
                {'name': 'Checker', 'source': True, 'columns': [{'kind': 'symbol'}], 'rows': [[self.checker_version]]},
                {'name': 'CheckedLaw', 'source': True, 'columns': [{'kind': 'symbol'}, {'kind': 'symbol'}],
                 'rows': [[key,law['checkerVersion']] for key,law in sorted(self.laws.items())]}]

    def summary(self):
        if not self.chain: return {'snapshot': self.snapshot, 'checkedDomainEvidence': [], 'domainContracts': copy.deepcopy(list(self.laws.values()))}
        sources = self._sources()
        var = {'var': 'c'}
        declarations = [{'name': n, 'columns': [{'kind': 'symbol'}], 'source': False, 'rows': []} for n in ('Passed', 'Failed', 'ReusableLaw')]
        rules = [{'head': [{'relation': n, 'terms': [var]}],
                  'body': [{'relation': 'ObservedClaim', 'terms': [var, {'const': flag}]}]}
                 for n, flag in (('Passed', True), ('Failed', False))]
        rules.append({'head':[{'relation':'ReusableLaw','terms':[var]}],
                      'body':[{'relation':'CheckedLaw','terms':[var,{'var':'v'}]},
                              {'relation':'Checker','terms':[{'var':'v'}]}]})
        began=time.monotonic()
        receipt = self.chain.query({'relations': sources+declarations, 'rules': rules, 'queries': ['Passed', 'Failed', 'ReusableLaw']})
        self.journal.append({'snapshot': self.snapshot, 'reusedComponents': receipt['reusedComponents'],
                             'freshComponents': receipt['freshComponents'], 'resultReference': receipt['resultReference'],
                             'seconds':time.monotonic()-began})
        return {'snapshot': self.snapshot, 'checkedDomainEvidence': copy.deepcopy(list(self.observations.values())),
                'domainContracts': [copy.deepcopy(self.laws[row[0]]) for row in receipt['result']['relations']['ReusableLaw']],
                'passedClaims': receipt['result']['relations']['Passed'],
                'failedClaims': receipt['result']['relations']['Failed'], 'resultReference': receipt['resultReference'],
                'scope': 'Exact constraints over receipted observations; not a proof of all implementation behavior.'}

    def close(self):
        if self.chain: self.chain.close()
        self.chain = None; self.observations.clear()
        self.laws.clear()
