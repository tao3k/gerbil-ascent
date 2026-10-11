"""Post-run receipt audit; does not call the provider or relabel thinking."""
import json,hashlib,sys
from pathlib import Path
root=Path('/private/var/folders/pj/n33bqzy94yn9wxggj3rny0d00000gn/T/ascent-clean-rebuild.5uyXYy/source');build=root.parent;sys.path[:0]=[str(root/'python/src'),str(build/'api')]
from ascent_test_support.evidence_chain_study import shared_check,branch_grade,shared_truth
frozen=build/'frozen';run=build/'run';plan=shared_check(frozen);rows=json.loads((run/'ledger.json').read_text());outcomes=[]
for row in rows:
 gross=0;previous={};known_supplied={};reads=0;task=plan['tasks'][row['case']]
 for c in row['calls']:
  folder=run/'calls'/f"{row['case']}-{row['arm']}"/f"{c['turn']}-{c['step']}";req=json.loads((folder/'request.json').read_text());meta=json.loads((folder/'response.json').read_text());term=meta.get('terminal') or {}
  assert not req.get('instructions') and req['reasoning']=={'effort':plan['reasoningEffort']}
  context=json.loads(req['input'][0]['content']);assert context['question']==plan['question'] and context['branch']==task['branches'][c['turn']]
  assert context['task']=={k:task[k] for k in ['edges','items','bonuses']}
  assert len(req['input'])==1 if c['step']==0 else req['input']==previous[c['turn']]
  assert c['suppliedAtoms']==known_supplied.get(c['turn'],[])
  assert hashlib.sha256((folder/'thinking.txt').read_bytes()).hexdigest()==c['thinkingSha256']
  u=c['usage']
  if c['grossTokens'] is not None:
   assert c['grossTokens']==u['input_tokens']+u['output_tokens'];gross+=c['grossTokens']
   assert c['atGrossTokens']==gross and u['input_tokens']<=c['inputReservation'] and u['output_tokens']<=c['outputCap']
   assert gross-c['grossTokens']+c['outputCap']+c['inputReservation']<=plan['totalBudget']
  if c['failure']:continue
  following=req['input']+term['output'];calls=[x for x in term['output'] if x['type']=='function_call'];packets=(c.get('nativePacket') or {}).get('returnedToolPackets',[])
  if packets:
   assert len(calls)==len(packets) and all(x['name']=='read_paths' for x in calls)
   for call,packet in zip(calls,packets):
    reads+=1;pairs=json.loads(call['arguments'])['pairs'];assert [o['conclusion']['atom'] for o in packet['observations']]==[['path',*p] for p in pairs]
    for o in packet['observations']:
     f=o['conclusion'];assert (f['status']=='verified')==shared_truth(task,f['atom'])
     assert ('support' in o)==(row['arm']=='scheme' and f['status']=='verified')
     if f['status']=='verified' and f['atom'] not in known_supplied.setdefault(c['turn'],[]):known_supplied[c['turn']].append(f['atom'])
    following.append({'type':'function_call_output','call_id':call['call_id'],'output':json.dumps(packet,sort_keys=True,separators=(',',':'))})
  else:
   for call in calls:following.append({'type':'function_call_output','call_id':call['call_id'],'output':'{"recorded":true}'})
  previous[c['turn']]=following
 for b in row['branches']:assert b['grade']==branch_grade(task,task['branches'][b['turn']],b['selected'])
 assert row['grossTokens']==gross<=plan['totalBudget']
 outcomes.append({'case':row['case'],'arm':row['arm'],'grossTokens':gross,'readCalls':reads,'submittedBranches':len(row['branches']),'stop':row['stop'],'failure':row['failure']})
result={'passed':True,'planSha256':hashlib.sha256((frozen/'plan.json').read_bytes()).hexdigest(),'producerHead':plan['sourceState']['head'],'inputsMatchCommittedHead':json.loads((frozen/'committed-gate/committed-input-check.json').read_text())['committedInputsVerified'],'audits':'Actual complete sibling history and paired tool IO; no solver instructions; input/output costs; prior-only supplied evidence; native outcomes vs BFS; independent objective grading. Known failures remain censored.','outcomes':outcomes}
(run/'audit.json').write_text(json.dumps(result,indent=2)+'\n');print('RUN_AUDIT_OK',outcomes)
