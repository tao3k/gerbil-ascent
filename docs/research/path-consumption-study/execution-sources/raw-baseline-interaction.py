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
        self.tools=[{'type':'function','name':'check_branches','description':
                    'Check local candidate path conditions during exploration. '+
                    'A branch may have one operation/arguments pair OR a conditions list of such pairs. '+
                    'All listed conditions must jointly hold; choose the local prerequisites yourself. '+
                    'Supported applies only to those declared conditions; unknown is not false. '+
                    'You may check up to 128 alternatives per call, reuse references, and continue reasoning. '+
                    'Available operations: '+json.dumps({n:o.description for n,o in self.operations.items()}),
                    'parameters':{'type':'object','properties':{'branches':{'type':'array','items':{
                        'type':'object','properties':{'id':{'type':'string'},'operation':{'type':'string'},
                        'arguments':{'type':'array','items':{}},'reference':{'type':'string'},
                        'conditions':{'type':'array','items':{'type':'object','properties':{'operation':{'type':'string'},
                            'arguments':{'type':'array','items':{}}},'required':['operation','arguments']}}},
                        'required':['id']}}},'required':['branches']},'strict':False}]

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
                        reference=identity({'result':receipt['resultReference'],'claim':key})
                        entry.update(status='supported' if supported else 'contradicted' if complete else 'unknown',
                                     complete=complete,resultReference=receipt['resultReference'],reference=reference,
                                     sourceIdentity=receipt['sourceIdentity'],pathIdentity=receipt['pathIdentity'],
                                     conditions=copy.deepcopy(conditions),reusedComponents=receipt['reusedComponents'],
                                     freshComponents=receipt['freshComponents'],retainedCompleted=receipt['retainedCompleted'],
                                     referenceRequested=branch.get('reference') is not None,
                                     reason='Completed check of every declared local condition' if supported or complete else 'No positive support; domain is not declared complete')
                        if len(conditions)==1:entry.update(operation=conditions[0]['operation'],arguments=copy.deepcopy(conditions[0]['arguments']))
                        self.references[reference]=(self.chain.source_identity,key)
                except (ValueError,EngineError) as error:
                    for item in items:item[1]['reason']='Check unavailable: '+str(error)[:512]
        if self.trajectory is not None:self.trajectory.checkpoint(model_call,output)
        return {'schema':'ascent.branch-feedback.v1','sourceIdentity':self.chain.source_identity,
                'scope':'model-declared-local-conditions','branches':output,'taskCorrectnessCertified':False,
                'seconds':time.monotonic()-started}

    def dispatch(self, call, *, model_call):
        try:
            if call.get('name')!='check_branches':raise ValueError('unknown tool')
            arguments=json.loads(call.get('arguments','{}'))
            return self.check(arguments.get('branches'),model_call=model_call)
        except (ValueError,TypeError,AttributeError) as error:
            return {'schema':'ascent.branch-feedback.v1','status':'unknown','reason':str(error),
                    'taskCorrectnessCertified':False}

    def replace(self,sources):
        self.chain.replace(sources);self.references.clear()

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
            self.history.append_result(call['call_id'],result)
            outputs.append({'callId':call['call_id'],'arguments':call.get('arguments'),
                            'feedback':result})
        return outputs
