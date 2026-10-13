# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Reuse completed Scheme components across different derivation requests.

Scheme owns SCCs, canonical rules, dependency fingerprints and query lowering.
Python transports source identities, DAG responses and completed-session certificates.
"""
import copy
from .evidence import EvidenceStore,identity


def normalize_contract(contract):
    """Accept equivalent JSON surface forms without weakening rule admission."""
    if not isinstance(contract,dict):raise ValueError('contract must be an object')
    value=copy.deepcopy(contract)
    value.setdefault('relations',[]);value.setdefault('rules',[])
    for rule in value['rules']:
        if isinstance(rule.get('head'),dict):rule['head']=[rule['head']]
    return value


def components(engine, program):
    return engine.request({'operation':'evidence-dag','action':'components','program':program})['components']


def evidence_dag(engine, program):
    """Return Scheme's dependency-first SCC DAG; this is a structural view."""
    return engine.request({'operation':'evidence-dag','action':'graph','program':program})


def canonical_rule(engine, rule):
    return engine.request({'operation':'evidence-dag','action':'canonical-rule','rule':rule})['rule']


class EvidenceChain:
    """One source generation, certified component DAG and result references."""
    def __init__(self,engine,sources,retain=True, *, limits=None, trajectory=None):
        self.engine=engine;self.sources=copy.deepcopy(sources);self.retain=retain
        self.limits=limits
        self.store=EvidenceStore(engine,sources,limits=limits);self.certificates={};self.results={}
        self.requests={}
        self.trajectory=trajectory
        if trajectory is not None and (trajectory.engine is not engine or trajectory.source_identity != self.source_identity):
            self.store.close()
            raise ValueError('trajectory must belong to this engine and source identity')

    @property
    def source_identity(self):return self.store.source_identity

    def scan(self,names):return self.store.scan(names)

    def query(self,program):
        program=copy.deepcopy(program)
        trusted={r['name']:r for r in self.sources}|self.store.materialized
        declarations={r['name']:r for r in program['relations'] if not r['source']}
        from . import EngineError
        try:
            dag=self.engine.request({'operation':'evidence-dag','action':'query','program':program,
                'trusted':trusted,'sources':[r['name'] for r in self.sources],
                'certificates':self.certificates,'requests':self.requests,
                'sourceIdentity':self.source_identity,'retain':self.retain})
        except EngineError as error:
            raise ValueError(str(error)) from error
        keys=dag['keys'];groups=dag['groups'];mapping=dag['mapping'];reused=dag['reused']
        lowered=dag['lowered'];fresh=dag['fresh'];request_key=dag['requestKey']
        # Every completed intermediate component is available to later rounds,
        # but only requested rows are exposed to the model.
        wanted=program['queries']
        receipt=self.store.query(lowered)
        rows=receipt['result']['relations'];aliases={p['originRelation']:p['relation'] for p in receipt['publishedEvidence']}
        if self.retain:
            self.requests[request_key]=copy.deepcopy((lowered,mapping))
            for descriptor in groups:
                group,key=descriptor['relations'],descriptor['fingerprint']
                if key not in self.certificates:self.certificates[key]={n:mapping.get(n,aliases.get(n)) for n in group}
        result={n:copy.deepcopy(rows[mapping.get(n,n)]) for n in wanted}
        handle=identity({'sourceIdentity':self.source_identity,'pathIdentity':receipt['pathIdentity'],'queries':wanted})
        self.results[handle]={'sourceIdentity':self.source_identity,'relations':result,'columns':{n:declarations[n]['columns'] for n in wanted if n in declarations}}
        self.results[handle]['components']=copy.deepcopy(groups)
        self.results[handle]['componentColumns']={n:copy.deepcopy(r['columns']) for n,r in declarations.items()}
        self.results[handle]['pathIdentity']=receipt['pathIdentity']
        feedback={'sourceIdentity':self.source_identity,'resultReference':handle,'pathIdentity':receipt['pathIdentity'],
                  'result':{'complete':True,'relations':result},'reusedComponents':reused,
                  'freshComponents':fresh,
                  'retainedCompleted':receipt['retainedCompleted'],
                  'availableClaims':[{'name':n,'fingerprint':keys[n],'rows':len(rows[mapping.get(n,n)])} for n in declarations] if self.retain else []}
        if not self.retain:
            self.store.close();self.store=EvidenceStore(self.engine,self.sources,limits=self.limits)
        if self.trajectory is not None:self.trajectory.evidence(feedback)
        return feedback

    def answer(self,reference,relation):
        if reference not in self.results:raise ValueError('unknown result reference')
        result=self.results[reference]
        if result['sourceIdentity']!=self.source_identity:raise ValueError('stale result reference')
        columns=result['columns'].get(relation)
        if not columns or len(columns)!=1:raise ValueError('answer reference must select a unary derived relation')
        if self.trajectory is not None:self.trajectory.direct_answer(reference)
        return copy.deepcopy(result['relations'][relation])

    def intermediates(self,reference,names):
        """Project completed native components, excluding requested answers.

        Relation selection is presentation only: current certificates and the
        native store establish completion and applicability. No final answer
        or host-recomputed closure is included in this packet.
        """
        result=self.results.get(reference)
        if result is None or result['sourceIdentity']!=self.source_identity:
            raise ValueError('unknown or stale intermediate reference')
        names=list(names)
        if not names or len(set(names))!=len(names):
            raise ValueError('select distinct intermediate relations')
        if any(n in result['relations'] for n in names):
            raise ValueError('requested answers cannot be intermediate evidence')
        selected={}
        for descriptor in result['components']:
            key=descriptor['fingerprint']
            certificate=self.certificates.get(key,{})
            for name in descriptor['relations']:
                if name in names and name in certificate:
                    selected[name]=(key,certificate[name])
        if set(selected)!=set(names):
            raise ValueError('intermediate relation is not currently completed')
        aliases=[selected[n][1] for n in names]
        rows=self.scan(aliases)['relations']
        return {'schema':'ascent.intermediate-evidence.v1',
                'sourceIdentity':self.source_identity,'resultReference':reference,
                'pathIdentity':result['pathIdentity'],
                'componentFingerprints':{n:selected[n][0] for n in names},
                'columns':{n:copy.deepcopy(result['componentColumns'][n]) for n in names},
                'facts':{n:copy.deepcopy(rows[selected[n][1]]) for n in names}}

    def replace(self,sources):
        self.store.replace(sources);self.sources=copy.deepcopy(sources)
        self.certificates.clear();self.results.clear();self.requests.clear()
        if self.trajectory is not None:self.trajectory.invalidate(self.source_identity)

    def close(self):self.store.close();self.certificates.clear();self.results.clear();self.requests.clear()
    def __enter__(self):return self
    def __exit__(self,*exc):self.close()
