# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Reuse completed Scheme components across different derivation requests.

Python fingerprints rule structure and transports certificates. Scheme admits
and executes every fresh component and every composition of imported results.
No Python implementation of relational inference is used here.
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


def components(program):
    declarations={r['name']:r for r in program['relations'] if not r['source']}
    graph={name:set() for name in declarations}
    for rule in program['rules']:
        heads={a['relation'] for a in rule['head']}
        for head in heads:
            if head not in graph:raise ValueError('rule head must be a declared derived relation')
            graph[head].update(heads-{head})
            graph[head].update(a['relation'] for a in rule['body'] if a['relation'] in graph)
    # Tarjan follows dependency edges, therefore emits dependencies first.
    index={};low={};stack=[];active=set();result=[]
    def visit(name):
        index[name]=low[name]=len(index);stack.append(name);active.add(name)
        for other in sorted(graph[name]):
            if other not in index:visit(other);low[name]=min(low[name],low[other])
            elif other in active:low[name]=min(low[name],index[other])
        if low[name]==index[name]:
            group=[]
            while True:
                other=stack.pop();active.remove(other);group.append(other)
                if other==name:break
            result.append(sorted(group))
    for name in sorted(graph):
        if name not in index:visit(name)
    return result


def canonical_rule(rule):
    # Alpha-renaming is safe; conjunction reordering is intentionally not inferred.
    value=copy.deepcopy(rule);variables={}
    for atom in value['head']+value['body']:
        atom.setdefault('not',False)
        for term in atom['terms']:
            if 'var' in term:
                variables.setdefault(term['var'],str(len(variables)))
                term['var']=variables[term['var']]
    return value


class EvidenceChain:
    """One source generation, certified component DAG and result references."""
    def __init__(self,engine,sources,retain=True):
        self.engine=engine;self.sources=copy.deepcopy(sources);self.retain=retain
        self.store=EvidenceStore(engine,sources);self.certificates={};self.results={}

    @property
    def source_identity(self):return self.store.source_identity

    def scan(self,names):return self.store.scan(names)

    def query(self,program):
        program=copy.deepcopy(program)
        trusted={r['name']:r for r in self.sources}|self.store.materialized
        # Check original authority before pruning any cached heads/declarations.
        seen=set()
        for relation in program['relations']:
            name=relation['name']
            if name in seen:raise ValueError('duplicate relation')
            seen.add(name)
            if name in trusted:
                if relation!=trusted[name]:raise ValueError('query changed source authority')
            elif relation.get('source') or relation.get('rows'):
                raise ValueError('derived evidence cannot introduce source facts')
        if not {r['name'] for r in self.sources}<=seen:raise ValueError('query omitted source authority')
        if any(a['relation'] in trusted for rule in program['rules'] for a in rule['head']):raise ValueError('query defines source heads')
        declarations={r['name']:r for r in program['relations'] if not r['source']}
        keys={};groups=[];mapping={};reused=[]
        for group in components(program):
            rules=[r for r in program['rules'] if any(a['relation'] in group for a in r['head'])]
            external=sorted({a['relation'] for r in rules for a in r['body'] if a['relation'] not in group})
            recursive=len(group)>1 or any(a['relation'] in group for r in rules for a in r['body'])
            key=identity({'sourceIdentity':self.source_identity,'relations':[declarations[n] for n in group],
                          'rules':sorted([canonical_rule(r) for r in rules],key=identity),
                          'dependencies':{n:keys.get(n,identity(trusted.get(n))) for n in external}})
            keys.update({n:key for n in group});groups.append((group,key,recursive,external))
            if self.retain and key in self.certificates:
                aliases=self.certificates[key]
                if all(n in aliases and aliases[n] in self.store.materialized for n in group):
                    mapping.update(aliases);reused.append({'relations':group,'fingerprint':key,'recursive':recursive,'dependencies':external})
        lowered=copy.deepcopy(program)
        lowered['relations']=[r for r in lowered['relations'] if r['name'] not in mapping]
        lowered['rules']=[r for r in lowered['rules'] if not any(a['relation'] in mapping for a in r['head'])]
        for rule in lowered['rules']:
            for atom in rule['body']:atom['relation']=mapping.get(atom['relation'],atom['relation'])
        # Every completed intermediate component is available to later rounds,
        # but only requested rows are exposed to the model.
        wanted=program['queries']
        lowered['queries']=list(dict.fromkeys(mapping.get(n,n) for n in wanted+list(declarations)))
        receipt=self.store.query(lowered)
        rows=receipt['result']['relations'];aliases={p['originRelation']:p['relation'] for p in receipt['publishedEvidence']}
        if self.retain:
            for group,key,recursive,external in groups:
                if key not in self.certificates:self.certificates[key]={n:mapping.get(n,aliases.get(n)) for n in group}
        result={n:copy.deepcopy(rows[mapping.get(n,n)]) for n in wanted}
        handle=identity({'sourceIdentity':self.source_identity,'pathIdentity':receipt['pathIdentity'],'queries':wanted})
        self.results[handle]={'sourceIdentity':self.source_identity,'relations':result,'columns':{n:declarations[n]['columns'] for n in wanted if n in declarations}}
        feedback={'sourceIdentity':self.source_identity,'resultReference':handle,'pathIdentity':receipt['pathIdentity'],
                  'result':{'complete':True,'relations':result},'reusedComponents':reused,
                  'freshComponents':[{'relations':g,'fingerprint':k,'recursive':r,'dependencies':d} for g,k,r,d in groups if not any(n in mapping for n in g)],
                  'retainedCompleted':receipt['retainedCompleted'],
                  'availableClaims':[{'name':n,'fingerprint':keys[n],'rows':len(rows[mapping.get(n,n)])} for n in declarations] if self.retain else []}
        if not self.retain:
            self.store.close();self.store=EvidenceStore(self.engine,self.sources)
        return feedback

    def answer(self,reference,relation):
        if reference not in self.results:raise ValueError('unknown result reference')
        result=self.results[reference]
        if result['sourceIdentity']!=self.source_identity:raise ValueError('stale result reference')
        columns=result['columns'].get(relation)
        if not columns or len(columns)!=1:raise ValueError('answer reference must select a unary derived relation')
        return copy.deepcopy(result['relations'][relation])

    def replace(self,sources):
        self.store.replace(sources);self.sources=copy.deepcopy(sources)
        self.certificates.clear();self.results.clear()

    def close(self):self.store.close();self.certificates.clear();self.results.clear()
    def __enter__(self):return self
    def __exit__(self,*exc):self.close()
