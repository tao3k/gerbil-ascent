# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Provider-independent local predicate tools backed by Scheme evidence.

Applications register trusted domain operations. Models send bindings, never
Scheme code or a whole-question query translation. Verdicts apply to the local
predicate only; an independent application grader owns task completion.
"""
import copy
import json
import time
from dataclasses import dataclass
from .derivations import EvidenceChain, normalize_contract
from .evidence import identity


@dataclass(frozen=True)
class EvidenceOperation:
    program: dict
    relation: str
    description: str
    complete: bool = False


class EvidenceInteraction:
    def __init__(self, engine, sources, operations, *, trajectory=None, retain=True):
        self.operations=copy.deepcopy(operations)
        if any(not isinstance(o,EvidenceOperation) or type(o.complete) is not bool for o in self.operations.values()):
            raise ValueError("register typed operations with explicit Boolean completeness")
        self.chain=EvidenceChain(engine,sources,retain=retain,trajectory=trajectory)
        self.trajectory=trajectory
        self.references={}
        self.paths={}
        self.sequence=0
        condition={'type':'object','properties':{'operation':{'type':'string','enum':list(self.operations)},
                   'arguments':{'type':'array','items':{},'description':'Ground tuple in the selected operation, in its documented column order.'}},
                   'required':['operation','arguments']}
        branch={'type':'object','properties':{'id':{'type':'string','description':'Your candidate-path identifier.'},
                'conditions':{'type':'array','minItems':1,'maxItems':16,'items':condition}},'required':['id','conditions']}
        self.tools=[{'type':'function','name':'check_branches','description':
                    'Check candidate reasoning paths. A path declares its local prerequisites as conditions; '+
                    'Scheme checks their conjunction. Select the conditions yourself. Supported means only those '+
                    'declared conditions hold; unknown is not false and no task answer is certified. '+
                    'The feedback columns decode each row; common provenance is stored once. '+
                    'Returned references can be rechecked or extended without retyping prerequisites. '+
                    'Available domain operations: '+json.dumps({n:o.description for n,o in self.operations.items()}),
                    'parameters':{'type':'object','properties':{'branches':{'type':'array','maxItems':128,'items':branch}},
                                  'required':['branches']},'strict':False},
                   {'type':'function','name':'reuse_paths','description':
                    'Recheck previously checked local paths by reference under current sources. '+
                    'This does not interpret a new question or certify a whole-task answer. Stale references return unknown.',
                    'parameters':{'type':'object','properties':{'references':{'type':'array','items':{'type':'string'},'maxItems':128}},
                                  'required':['references']},'strict':False},
                   {'type':'function','name':'extend_paths','description':
                    'Extend a checked local path with additional prerequisites you select. '+
                    'All previous and new conditions must jointly hold in the same current source generation.',
                    'parameters':{'type':'object','properties':{'paths':{'type':'array','maxItems':128,'items':{
                        'type':'object','properties':{'id':{'type':'string'},'reference':{'type':'string'},
                        'conditions':{'type':'array','items':condition}},'required':['id','reference','conditions']}}},
                                  'required':['paths']},'strict':False}]

    def check(self, branches, *, model_call):
        if not isinstance(branches,list) or not 1<=len(branches)<=128:
            raise ValueError('check one to 128 branches')
        if any(not isinstance(b,dict) or not isinstance(b.get('id'),str) or not b['id'] for b in branches):
            raise ValueError('branch identities required')
        if len({b['id'] for b in branches})!=len(branches):raise ValueError('distinct branch identities required')
        from . import EngineError
        started=time.monotonic();output=[];groups={}
        sources={r['name']:r for r in self.chain.sources}
        for branch in branches:
            entry={'id':branch['id'],'status':'unknown','complete':False};output.append(entry)
            conditions=branch.get('conditions',[{'operation':branch.get('operation'),'arguments':branch.get('arguments')}])
            if not isinstance(conditions,list) or not 1<=len(conditions)<=16:
                entry['reason']='Declare one to sixteen local conditions';continue
            program=None;program_identity=None;atoms=[];complete=True;valid=True
            for condition in conditions:
                if not isinstance(condition,dict):valid=False;break
                operation=self.operations.get(condition.get('operation'));arguments=condition.get('arguments')
                if operation is None or not isinstance(arguments,list):valid=False;break
                candidate=normalize_contract(operation.program);candidate['queries']=[]
                candidate['relations']=[copy.deepcopy(sources.get(r['name'],r)) if r['source'] else r for r in candidate['relations']]
                declaration=next((r for r in candidate['relations'] if r['name']==operation.relation),None)
                if declaration is None or len(arguments)!=len(declaration['columns']) or any(not isinstance(v,(str,int,bool,float)) for v in arguments):valid=False;break
                key=identity(candidate)
                if program_identity is not None and key!=program_identity:valid=False;break
                program=candidate;program_identity=key;complete=complete and operation.complete
                atoms.append({'relation':operation.relation,'terms':[{'const':v} for v in arguments]})
            if not valid:
                entry['reason']='Unsupported bindings or incompatible domain programs';continue
            request_identity=identity({'conditions':conditions,'program':program,'complete':complete})
            prior=branch.get('reference')
            if prior is not None and self.references.get(prior)!=(self.chain.source_identity,request_identity):
                entry['reason']='Unknown, mismatched, or invalidated evidence reference';continue
            group=groups.setdefault(program_identity,{'program':program,'items':[]})
            group['items'].append((branch,entry,request_identity,atoms,complete,conditions))
        # Native conjunction checks share bounded batches. Native rows, not
        # host Boolean evaluation, determine which candidate conditions hold.
        for group in groups.values():
            base_program=group['program'];all_items=group['items']
            budget=128-len(base_program['rules'])-len(base_program['relations'])
            if budget<1:
                for item in all_items:item[1]['reason']='Registered operation exhausts native rule capacity'
                continue
            for offset in range(0,len(all_items),budget):
                program=copy.deepcopy(base_program);items=all_items[offset:offset+budget]
                name='checked_'+identity([(b['id'],key) for b,e,key,atoms,complete,conditions in items])[:20]
                if any(r['name']==name for r in program['relations']):raise ValueError('reserved check predicate collision')
                program['relations'].append({'name':name,'source':False,'columns':[{'kind':'symbol'}],'rows':[]})
                for branch,entry,key,atoms,complete,conditions in items:
                    program['rules'].append({'head':[{'relation':name,'terms':[{'const':branch['id']}]}],'body':atoms})
                program['queries']=[name]
                try:
                    receipt=self.chain.query(program)
                    matched={r[0] for r in receipt['result']['relations'][name]}
                    for branch,entry,key,atoms,complete,conditions in items:
                        supported=branch['id'] in matched
                        self.sequence+=1
                        reference='path_'+str(self.sequence)
                        entry.update(status='supported' if supported else 'contradicted' if complete else 'unknown',
                                     complete=complete,resultReference=receipt['resultReference'],reference=reference,
                                     sourceIdentity=receipt['sourceIdentity'],pathIdentity=receipt['pathIdentity'],
                                     conditions=copy.deepcopy(conditions),reusedComponents=receipt['reusedComponents'],
                                     freshComponents=receipt['freshComponents'],retainedCompleted=receipt['retainedCompleted'],
                                     referenceRequested=branch.get('reference') is not None,
                                     reason='Completed check of every declared local condition' if supported or complete else 'No positive support; domain is not declared complete')
                        if len(conditions)==1:entry.update(operation=conditions[0]['operation'],arguments=copy.deepcopy(conditions[0]['arguments']))
                        self.references[reference]=(self.chain.source_identity,key)
                        self.paths[reference]={'id':branch['id'],'conditions':copy.deepcopy(conditions)}
                except (ValueError,EngineError) as error:
                    for item in items:item[1]['reason']='Check unavailable: '+str(error)[:512]
        if self.trajectory is not None:self.trajectory.checkpoint(model_call,output)
        return {'schema':'ascent.branch-feedback.v1','sourceIdentity':self.chain.source_identity,
                'scope':'model-declared-local-conditions','branches':output,'taskCorrectnessCertified':False,
                'seconds':time.monotonic()-started}

    def reuse(self, references, *, model_call):
        if not isinstance(references,list) or not 1<=len(references)<=128 or any(not isinstance(r,str) for r in references):
            raise ValueError('select one to 128 path references')
        if len(set(references))!=len(references):raise ValueError('select distinct references')
        branches=[]
        for i,reference in enumerate(references):
            path=self.paths.get(reference)
            branches.append({**copy.deepcopy(path),'id':path['id']+':reuse:'+str(i),'reference':reference} if path else
                            {'id':'unknown:'+str(i),'operation':'','arguments':[],'reference':reference})
        result=self.check(branches,model_call=model_call)
        for b,reference in zip(result['branches'],references):b['requestedReference']=reference
        return result

    def extend(self, paths, *, model_call):
        if not isinstance(paths,list) or not 1<=len(paths)<=128:raise ValueError('select one to 128 paths')
        branches=[]
        for path in paths:
            if not isinstance(path,dict) or not isinstance(path.get('id'),str):raise ValueError('path identity required')
            previous=self.paths.get(path.get('reference'))
            conditions=path.get('conditions')
            if previous is None or not isinstance(conditions,list) or not conditions:
                branches.append({'id':path['id'],'operation':'','arguments':[]});continue
            branches.append({'id':path['id'],'conditions':copy.deepcopy(previous['conditions'])+copy.deepcopy(conditions)})
        result=self.check(branches,model_call=model_call)
        for b,path in zip(result['branches'],paths):b['extendedReference']=path.get('reference')
        return result

    def dispatch(self, call, *, model_call):
        try:
            arguments=json.loads(call.get('arguments','{}'))
            if call.get('name')=='check_branches':return self.check(arguments.get('branches'),model_call=model_call)
            if call.get('name')=='reuse_paths':return self.reuse(arguments.get('references'),model_call=model_call)
            if call.get('name')=='extend_paths':return self.extend(arguments.get('paths'),model_call=model_call)
            raise ValueError('unknown evidence tool')
        except (ValueError,TypeError,AttributeError) as error:
            return {'schema':'ascent.branch-feedback.v1','status':'unknown','reason':str(error),
                    'taskCorrectnessCertified':False}

    def replace(self,sources):
        self.chain.replace(sources);self.references.clear();self.paths.clear()

    def close(self):self.chain.close()
    def __enter__(self):return self
    def __exit__(self,*exc):self.close()


class EvidenceConversation:
    """Pair model tools with evidence from the first response onward.

    The application owns provider invocation and independent grading. Full
    provider reasoning items are forwarded opaquely by ResponseHistory.
    """
    def __init__(self, question, interaction):
        from .conversation import ResponseHistory
        self.history=ResponseHistory(question)
        self.interaction=interaction

    def accept(self, response, *, call_id, round):
        ledger=self.interaction.trajectory
        if ledger is not None:ledger.model_call(call_id,round,response.get('usage'))
        if response.get('status')!='completed':
            raise ValueError('provider response is incomplete; usage was retained')
        calls=self.history.append_response(response)
        outputs=[]
        for call in calls:
            result=self.interaction.dispatch(call,model_call=call_id)
            exposed=compact_feedback(result)
            self.history.append_result(call['call_id'],exposed)
            outputs.append({'callId':call['call_id'],'toolName':call.get('name'),'arguments':call.get('arguments'),
                            'feedback':result,'exposedFeedback':exposed})
        return outputs


def compact_feedback(packet):
    """Lossless factoring of native verdict/provenance fields, no inference."""
    packet=copy.deepcopy(packet)
    branches=packet.pop('branches',None)
    if not isinstance(branches,list) or not branches:return {**packet,**({'branches':branches} if branches is not None else {})}
    # Distinct native batch receipts form groups; no authority fields discarded.
    groups={}
    for b in branches:
        key=b.get('resultReference','unknown:'+b.get('id',''))
        groups.setdefault(key,[]).append(b)
    encoded=[]
    for rows in groups.values():
        common={k:v for k,v in rows[0].items() if all(k in row and row[k]==v for row in rows)}
        fields=sorted(set().union(*(r.keys() for r in rows))-common.keys())
        # A presence mask distinguishes a missing field from a null value.
        values=[[r.get(k) for k in fields] for r in rows]
        presence=[[k in r for k in fields] for r in rows]
        encoded.append({'common':common,'fields':fields,'rows':values,'present':presence})
    return {**packet,'encoding':'ascent.branch-columns.v1','groups':encoded,'branchOrder':[b['id'] for b in branches]}


def expand_feedback(packet):
    packet=copy.deepcopy(packet)
    if packet.get('encoding')!='ascent.branch-columns.v1':return packet
    packet.pop('encoding');groups=packet.pop('groups');branches=[]
    for group in groups:
        for values,present in zip(group['rows'],group['present']):
            branches.append({**group['common'],**{k:v for k,v,p in zip(group['fields'],values,present) if p}})
    # Grouping changes row order; retain original position explicitly below.
    order=packet.pop('branchOrder')
    by_id={b['id']:b for b in branches};packet['branches']=[by_id[i] for i in order]
    return packet
