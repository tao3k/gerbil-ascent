"""Native pre-model request preview. No provider, key, or paid calls."""
import sys,os,json,hashlib
from pathlib import Path
build=Path(sys.argv[1]).resolve();root=build/'source';sys.path[:0]=[str(root/'python/src'),str(build/'api' if (build/'api').exists() else build/'frozen/api-runtime')]
from ascent_test_support.evidence_chain_study import shared_check,branch_tasks,branch_observe,shared_source,branch_input_reservation,branch_submission_context,branch_grade
from ascent_engine import Engine
from ascent_engine.evidence import ComputationalEvidence
frozen=build/'frozen';plan=shared_check(frozen);out=build/'preview';out.mkdir(exist_ok=False);rows=[]
# The exact old task and frozen independent objective judge stay unchanged.
old=Path(__file__).resolve().parent/'reference-plan.json'
previous=json.loads(old.read_text())
assert plan['tasks']==previous['tasks'] and plan['independentJudge']==previous['independentJudge'] and plan['question']==previous['question'] and plan['totalBudget']==previous['totalBudget']
with Engine() as engine:
 for case,task in enumerate(plan['tasks']):
  facts=[]
  for arm in plan['arms']:
   with ComputationalEvidence(engine) as store:
    packet=None
    for branch in task['branches']:
     current=None if arm=='baseline' else branch_observe(store,task,shared_source(task),support=arm=='scheme')
     if packet is not None:assert packet==current,'entry evidence changed between branches'
     packet=current
     if current is not None:
      if branch['id']==0:facts.append([o['conclusion']['status'] for o in current['observations']])
      assert bool(current.get('supportNodes'))==(arm=='scheme')
      assert ('roots' in current['observations'][0].get('support',{}))==(arm=='scheme')
     context={'question':plan['question'],'task':{k:task[k] for k in ['edges','items','bonuses']},'branch':branch}
     if packet is not None:context['nativeEvidence']=packet
     request={'model':plan['model'],'input':[{'role':'user','content':json.dumps(context,separators=(',',':'))}],
              'tools':[plan['tool']],'tool_choice':'auto',
              'reasoning':{'effort':plan['reasoningEffort']},'stream':True,'store':False}
     bound=branch_input_reservation(request,None,[],plan['inputPadding']);reserved=bound+plan['maxOutputTokens']+plan['inputPadding']+plan['finalizationOutputCap']
     assert plan['totalBudget']-bound-reserved>=plan['maxOutputTokens'],'first checkpoint not feasible'
     request['max_output_tokens']=plan['maxOutputTokens']
     file=out/f'{case}-{arm}-{branch["id"]}.json';file.write_text(json.dumps(request,indent=2)+'\n')
     rows.append({'case':case,'arm':arm,'branch':branch['id'],'file':file.name,'sha256':hashlib.sha256(file.read_bytes()).hexdigest(),'inputReservation':bound,'entryBeforeThinking':True,'initialOutputCap':plan['maxOutputTokens']})
    if arm!='baseline':assert store.stats()['proof-builds']==1 and store.stats()['hits']==5
  assert len(facts)==2 and facts[0]==facts[1],'Fact/Scheme conclusions differ'
fixture=json.loads((frozen/'inputs/tools/research/output-check-fixture.json').read_text());req=fixture['request'];req['input']+=branch_submission_context(fixture['terminal']);req.update(reasoning={'effort':'none'},tools=[plan['tool']],tool_choice={'type':'function','name':'submit_selection'},max_output_tokens=plan['finalizationOutputCap'])
(out/'output-qualification-request.json').write_text(json.dumps(req,indent=2)+'\n')
record={'passed':True,'producerHead':plan['sourceState']['head'],'planSha256':hashlib.sha256((frozen/'plan.json').read_bytes()).hexdigest(),'taskJudgeQuestionAndBudgetIdenticalToPrevious':True,'actualNativeObservationBeforeAllBranchInputs':True,'nativeProofBuildsPerSourceAndArm':1,'nativeHitsPerSourceAndArm':5,'firstInputRequests':rows,'realOutputQualification':'NOT_RUN_REQUIRES_EXTERNAL_APPROVAL','realSolverCalls':0}
(out/'preflight.json').write_text(json.dumps(record,indent=2)+'\n');print('ENTRY_NATIVE_PREFLIGHT_OK',len(rows),flush=True)
