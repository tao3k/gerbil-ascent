import json,hashlib,subprocess,shutil,sys
from pathlib import Path
root=Path.cwd(); base=root/'.cache/ascent/shared-premise'; frozen=base/'final-frozen'; run=base/'model-run'; doc=root/'docs/research/agent-inference/fact-reuse-results/shared-premise-diagnostic'
sys.path[:0]=[str(base/'source-snapshot/python/src'),str(frozen/'api-runtime')]
from ascent_test_support.evidence_chain_study import shared_check,shared_truth
plan=shared_check(frozen); rows=json.loads((run/'ledger.json').read_text()); labels=json.loads((run/'annotation-ledger.json').read_text())
assert len(rows)==6 and sum(len(r['calls']) for r in rows)==18
for r in rows:
 task=plan['tasks'][r['case']]; gross=0; prev=[]
 for c in r['calls']:
  folder=run/'calls'/f"{r['case']}-{r['arm']}"/str(c['turn']); req=json.loads((folder/'request.json').read_text()); u=c['usage'];gross+=u['input_tokens']+u['output_tokens']
  assert c['grossTokens']==u['input_tokens']+u['output_tokens'] and c['atGrossTokens']==gross
  assert u['input_tokens']<=c['inputReservation'] and req['max_output_tokens']==c['outputCap']
  assert c['outputCap']+c['inputReservation']+gross-c['grossTokens']<=plan['totalBudget']
  assert c['status']=='completed' and not c['failure']
  assert c['expected']==[i for i in task['schedule'][c['turn']] if shared_truth(task,['ready',i])]
  assert c['correct'] and sorted(c['answer'])==c['expected']
  assert hashlib.sha256((folder/'thinking.txt').read_bytes()).hexdigest()==c['thinkingSha256']
  assert not req.get('instructions')
  context=json.loads(next(x['content'] for x in reversed(req['input']) if x.get('role')=='user'))
  assert context['question']==plan['question'] and context['obligations']==[n for n in task['needs'] if n[0] in task['schedule'][c['turn']]]
  # Every earlier reasoning item is replayed in full; callbacks refer to actual preceding calls.
  if prev: assert req['input'][:len(prev)]==prev
  prev=req['input']
  calls={x['call_id'] for x in req['input'] if x.get('type')=='function_call'}
  for x in req['input']:
   if x.get('type')=='function_call_output':assert x['call_id'] in calls and json.loads(x['output'])=={'recorded':True}
 assert gross==r['grossTokens']<=plan['totalBudget']
for case in range(2):
 arms={r['arm']:r for r in rows if r['case']==case}
 for turn in range(3):
  f=arms['facts']['calls'][turn]['nativePacket'];s=arms['scheme']['calls'][turn]['nativePacket']
  assert f['facts']==s['facts'] and f['scope']==s['scope']
 shared=[next(x for x in c['nativePacket']['fragments'] if x['atom']==plan['tasks'][case]['sharedAtom']) for c in arms['scheme']['calls']]
 assert shared[0]==shared[1]==shared[2]
print('AUDIT passed: costs, questions, complete-history prefix, paired callbacks, independent answers and native packet correspondence')
# Separate cross-question repeats from within-question repeats; do not alter frozen labels.
repeat_scope=[]; excerpts=['# Literal thinking evidence','', 'Post-run inspection of frozen labels; no relabeling or new solver call. Counts remain lower bounds. A repeated-ready label within one question does not establish a cross-question repetition.','']
for phase in labels:
 seen={};cross=within=supplied=0
 for c in phase['calls']:
  for e in c['accepted']:
   if not e['qualifiedPositive']:continue
   key=json.dumps(e['atom']); prior=seen.get(key)
   if prior is not None:
    if prior<c['turn']:cross+=1
    else:within+=1
   seen[key]=c['turn']
   if e.get('suppliedPremiseRederived'):supplied+=1
   if prior is not None or e.get('suppliedPremiseRederived'):
    excerpts.extend([f"## Case {phase['case']} / {phase['arm']} / pass {phase['pass']} / question {c['turn']}", '',f"Atom: `{e['atom']}`. Supplied premise rederived: {e.get('suppliedPremiseRederived',False)}; prior question: {prior}.",'', '> '+e['quote'],''])
 repeat_scope.append({k:phase[k] for k in ['case','arm','pass']}|{'crossQuestionQualifiedRepeats':cross,'withinQuestionQualifiedRepeats':within,'suppliedPremiseRederivations':supplied})
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip();blocked=[];drift=[]
for name,h in plan['inputs'].items():
 p=subprocess.run(['git','show',f'HEAD:{name}'],cwd=root,capture_output=True)
 if p.returncode or hashlib.sha256(p.stdout).hexdigest()!=h:blocked.append(name)
 path=root/name
 if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest()!=h:drift.append(name)
result={'auditPassed':True,'frozenPlanSha256':hashlib.sha256((frozen/'plan.json').read_bytes()).hexdigest(),'frozenInputCount':len(plan['inputs']),'checkedSolverCalls':18,'sourceSnapshot':plan['sourceState'],'currentWorkspaceHead':head,'currentWorkspaceDifferentInputs':drift,'committedInputsVerified':not blocked,'committedGateBlockedPaths':blocked,'repeatScope':repeat_scope,'knownSolverTokens':sum(r['grossTokens'] for r in rows),'knownAnnotationTokens':sum(c['grossTokens'] or 0 for x in labels for c in x['calls']),'scope':'Post-run audit of frozen snapshot; current dirty workspace and clean committed build are separate gates.'}
(doc/'postrun-audit.json').write_text(json.dumps(result,indent=2)+'\n');(doc/'thinking-evidence.md').write_text('\n'.join(excerpts)+'\n');shutil.copy2(__file__,doc/'postrun-audit.py')
print('cross-question repeats',sum(x['crossQuestionQualifiedRepeats'] for x in repeat_scope),'committed blocked',len(blocked),'current drift',len(drift))
