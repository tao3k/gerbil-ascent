# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Retained, source-bound Scheme evidence for an iterative inference client."""
import copy
import hashlib
import json


def identity(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()


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
        referenced={a['relation'] for r in program['rules'] for a in r['body']}|set(program['queries'])
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
