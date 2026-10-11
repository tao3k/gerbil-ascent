# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Retained, source-bound Scheme evidence for an iterative inference client."""
import copy
import hashlib
import json
from .operators import dependencies


def identity(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()


def compact_observation(packet):
    """Lossless column projection of an already-read native packet; no inference.

    Column names travel with the rows. Common values are factored once, but all
    statuses, scope digests, handles, roots and named ancestors remain present.
    Heterogeneous conclusions retain their original object representation.
    """
    packet = copy.deepcopy(packet)
    observations = packet.pop('observations')
    facts = [o['conclusion'] for o in observations]
    if not facts or any(set(f) != set(facts[0]) for f in facts):
        return {'encoding': 'native-objects', 'packet': {**packet, 'observations': observations}}
    common = {k:v for k,v in facts[0].items() if all(f[k] == v for f in facts)}
    fields = [k for k in facts[0] if k not in common]
    result = {'encoding': 'native-columns', **packet, 'commonConclusion': common,
              'conclusionFields': fields, 'conclusions': [[f[k] for k in fields] for f in facts]}
    extras = [{k:v for k,v in o.items() if k != 'conclusion'} for o in observations]
    # Reference an existing root column only when the native values match exactly.
    # Absence has no positive support; it never acquires an invented empty proof.
    linked = [e == {'support': {'roots': f.get('support-nodes')}} and
              'support-nodes' in f for f,e in zip(facts,extras)]
    if any(linked):
        result['supportRootsFromConclusion'] = linked
        extras = [{} if link else e for e,link in zip(extras,linked)]
    if any(extras): result['observationExtras'] = extras
    if 'supportNodes' in result:
        nodes = result.pop('supportNodes')
        fields = ['id', 'kind', 'atom', 'ruleLabel', 'parents']
        if any(set(n) != set(fields) for n in nodes): raise ValueError('unknown native node fields')
        predicates = {}
        for n in nodes:
            atom=n['atom']
            if not isinstance(atom,list) or not atom or not isinstance(atom[0],str): break
            if n['kind'] in predicates and predicates[n['kind']] != atom[0]: break
            predicates[n['kind']] = atom[0]
        else:
            if nodes:
                # This dictionary is observed data, not a rule about node kinds.
                fields = ['id', 'kind', 'arguments', 'ruleLabel', 'parents']
                result['nodeAtomPredicates'] = predicates
        result.update(nodeFields=fields, supportNodes=[
            [n['atom'][1:] if k=='arguments' else n[k] for k in fields] for n in nodes])
    return result


def expand_observation(packet):
    """Restore every native field from compact_observation, without re-evaluation."""
    packet = copy.deepcopy(packet)
    encoding = packet.pop('encoding')
    if encoding == 'native-objects': return packet['packet']
    if encoding != 'native-columns': raise ValueError('unknown observation encoding')
    common = packet.pop('commonConclusion'); fields = packet.pop('conclusionFields')
    rows = packet.pop('conclusions'); extras = packet.pop('observationExtras', [{} for _ in rows])
    if len(extras) != len(rows) or any(len(r) != len(fields) for r in rows):
        raise ValueError('observation column shape')
    packet['observations'] = [{'conclusion': {**common, **dict(zip(fields, r))}, **e} for r,e in zip(rows, extras)]
    linked = packet.pop('supportRootsFromConclusion', [False for _ in rows])
    if len(linked)!=len(rows) or any(type(v) is not bool for v in linked):
        raise ValueError('support root reference shape')
    for observation,link in zip(packet['observations'],linked):
        if link:
            if 'support' in observation or 'support-nodes' not in observation['conclusion']:
                raise ValueError('conflicting support root reference')
            observation['support']={'roots':copy.deepcopy(observation['conclusion']['support-nodes'])}
    if 'supportNodes' in packet:
        fields = packet.pop('nodeFields')
        if any(len(r) != len(fields) for r in packet['supportNodes']): raise ValueError('node column shape')
        packet['supportNodes'] = [dict(zip(fields, r)) for r in packet['supportNodes']]
        predicates=packet.pop('nodeAtomPredicates', None)
        if predicates is not None:
            for node in packet['supportNodes']:
                node['atom']=[predicates[node['kind']], *node.pop('arguments')]
    return packet


class ComputationalEvidence:
    """Thin C ABI binding to the bounded Scheme proof store.

    Candidate data is inert: JSON strings represent Scheme symbols in the
    existing candidate DSL. Source authenticity remains the caller's duty.
    This store is distinct from materialized relation aliases in EvidenceStore.
    """
    def __init__(self, engine):
        self.engine = engine
        self.owner = engine.request({'operation': 'computational-evidence',
                                     'action': 'open'})['owner']

    def _call(self, action, **fields):
        if self.owner is None:
            raise ValueError('computational evidence owner closed')
        return self.engine.request({'operation': 'computational-evidence',
                                    'action': action, 'owner': self.owner, **fields})

    def resolve(self, source, candidate):
        return dict(self._call('resolve', source=source, candidate=candidate))

    def fact(self, source, candidate, handle, atom):
        return dict(self._call('fact', source=source, candidate=candidate,
                               handle=handle, atom=atom))

    def fragment(self, source, candidate, handle, atom):
        result = dict(self._call('fragment', source=source, candidate=candidate,
                                handle=handle, atom=atom))
        if 'fact' in result:
            result['fact'] = dict(result['fact'])
        return result

    def stats(self):
        return dict(self._call('stats'))

    def observe(self, source, candidate, handle, atoms, *, support=False):
        """Read native conclusions with optional named, ancestor-closed support.

        This is wire projection, not Python inference or an evidence admission
        bypass. Unknown/stale conclusions stay unknown. Callers pair this data
        with the model's actual tool call, rather than fabricating a call id.
        """
        if not isinstance(atoms, list) or not 0 < len(atoms) <= 32:
            raise ValueError('one to 32 atoms required')
        observations = []; scope = None; support_nodes = {}
        for atom in atoms:
            fact = self.fact(source, candidate, handle, atom)
            observation = {'conclusion': fact}
            if 'scope' in fact:
                current_scope = dict(fact.pop('scope'))
                if scope is not None and current_scope != scope:
                    raise ValueError('mixed native observation scopes')
                scope = current_scope
            if support and fact['status'] == 'verified':
                fragment = self.fragment(source, candidate, handle, atom)
                if fragment['status'] != 'verified':
                    raise ValueError('native fragment changed during observation')
                observation['support'] = {'roots': fragment['roots']}
                for n in fragment['nodes']:
                    node = {'id': n[0], 'kind': n[1], 'atom': [n[2], *n[3]],
                            'ruleLabel': n[4], 'parents': n[5]}
                    if n[0] in support_nodes and support_nodes[n[0]] != node:
                        raise ValueError('mixed native support nodes')
                    support_nodes[n[0]] = node
            observations.append(observation)
        result = {'observations': observations}
        if scope is not None: result['scope'] = scope
        if support_nodes: result['supportNodes'] = list(support_nodes.values())
        return result

    def close(self):
        if self.owner is not None:
            self._call('close')
            self.owner = None

    def __enter__(self): return self
    def __exit__(self, *exc): self.close()


class EvidenceStore:
    """Scheme validates and evaluates rules; this binding owns retained handles.

    Complete evidence means consequences of admitted rules over the current
    finite source. It does not certify the rules match natural-language intent.
    """
    def __init__(self,engine,sources):
        if any(not r.get('source') for r in sources):raise ValueError('trusted sources required')
        if len({r['name'] for r in sources})!=len(sources):raise ValueError('duplicate source names')
        self.engine=engine;self.sources=copy.deepcopy(sources);self.sessions={};self.dirty=set()
        self.materialized={};self.dependencies={}
        with engine.open({'relations':self.sources,'rules':[],'queries':[r['name'] for r in self.sources]}):pass

    @property
    def source_identity(self):return identity(self.sources)

    def scan(self,names):
        available={r['name']:r for r in self.sources}|self.materialized
        if any(n not in available for n in names):raise ValueError('unknown source scan')
        return {'sourceIdentity':self.source_identity,'relations':{n:copy.deepcopy(available[n]['rows']) for n in names}}

    def query(self,program):
        if set(program)!={'relations','rules','queries'}:raise ValueError('evidence program fields')
        program=copy.deepcopy(program)
        base={r['name']:r for r in self.sources}
        trusted=base|self.materialized;seen=set();derived=[]
        referenced=dependencies([a for r in program['rules'] for a in r['body']])|set(program['queries'])
        used=referenced & set(self.materialized)
        present={r['name'] for r in program['relations']}
        for name in sorted(used-present):program['relations'].append(copy.deepcopy(self.materialized[name]))
        for relation in program['relations']:
            name=relation['name']
            if name in seen:raise ValueError('duplicate relation')
            seen.add(name)
            if name in trusted:
                if relation!=trusted[name]:raise ValueError('query changed source authority')
            else:
                if relation.get('source') or relation.get('rows'):raise ValueError('derived evidence cannot introduce source facts')
                derived.append(relation)
        if not set(base)<=seen:raise ValueError('query omitted source authority')
        if any(a['relation'] in trusted for rule in program['rules'] for a in rule['head']):
            raise ValueError('query defines source heads')
        key=identity({'sourceSchema':[{k:v for k,v in r.items() if k!='rows'} for r in self.sources],
                      'evidenceSchema':[{k:v for k,v in self.materialized[name].items() if k!='rows'} for name in sorted(used)],
                      'derived':derived,'rules':program['rules'],'queries':program['queries']})
        reused=key in self.sessions
        if not reused:
            self.sessions[key]=self.engine.open(program);self.dependencies[key]=used
        session=self.sessions[key]
        completed_hit=reused and key not in self.dirty
        try:
            result=session.run(0 if completed_hit else 1000000000)
            if not result['complete']:raise ValueError('evidence evaluation incomplete')
            self.dirty.discard(key)
        except Exception:
            session.close();self.sessions.pop(key,None);self.dependencies.pop(key,None);self.dirty.discard(key)
            raise
        declarations={r['name']:r for r in program['relations']}
        published=[]
        for name,rows in result['relations'].items():
            if name in trusted:continue
            alias='evidence_'+key[:16]+'_'+name
            if alias in base:raise ValueError('evidence alias conflicts with source')
            relation=copy.deepcopy(declarations[name])
            relation.update(name=alias,source=True,rows=copy.deepcopy(rows))
            self.materialized[alias]=relation
            published.append({'relation':alias,'originRelation':name,'columns':relation['columns']})
        return {'sourceIdentity':self.source_identity,'pathIdentity':key,
                'retainedPath':reused,'retainedCompleted':completed_hit,'result':result,
                'publishedEvidence':published}

    def replace(self,sources):
        previous={r['name']:r for r in self.sources};current={r['name']:r for r in sources}
        if set(current)!=set(previous) or len(current)!=len(sources):raise ValueError('source set changed')
        for name,relation in current.items():
            if {k:v for k,v in relation.items() if k!='rows'}!={k:v for k,v in previous[name].items() if k!='rows'}:
                raise ValueError('source schema changed; admit a new evidence store')
        # Admit the whole replacement before mutating retained sessions.
        with self.engine.open({'relations':sources,'rules':[],'queries':list(current)}):pass
        try:
            # Materialized subgoals belong to the old source. Invalidate their
            # consumers, retaining only paths that directly use base sources.
            for key in list(self.sessions):
                if self.dependencies[key]:
                    self.sessions.pop(key).close();self.dependencies.pop(key);self.dirty.discard(key)
            for session in self.sessions.values():
                session.replace([{'relation':r['name'],'rows':r['rows']} for r in sources])
        except Exception:
            self.close()
            raise
        self.sources=copy.deepcopy(sources)
        self.materialized.clear()
        # Updated sessions need evaluation rather than a completed zero-budget hit.
        self.dirty=set(self.sessions)

    def close(self):
        for session in self.sessions.values():session.close()
        self.sessions.clear()
        self.dirty.clear()
        self.materialized.clear();self.dependencies.clear()

    def __enter__(self):return self
    def __exit__(self,*exc):self.close()
