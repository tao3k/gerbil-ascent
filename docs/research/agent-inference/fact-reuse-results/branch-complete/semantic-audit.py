"""Offline audit of blind proposals, coverage admission and local truth checks."""
import sys,json,hashlib
from pathlib import Path
b=Path(sys.argv[1]);sys.path[:0]=[str(b/'source/python/src'),str(b/'api' if (b/'api').exists() else b/'frozen/api-runtime')]
from ascent_test_support.evidence_chain_study import shared_check,branch_semantic_validate,shared_validate_label
plan=shared_check(b/'frozen');rows=json.loads((b/'run/ledger.json').read_text());reviews=json.loads((b/'run/semantic-ledger.json').read_text());prior={};summary=[]
for rec in reviews:
 key=(rec['case'],rec['arm']);task=plan['tasks'][rec['case']];earlier=prior.setdefault(key,[])
 call=next(c for r in rows if (r['case'],r['arm'])==key for c in r['calls'] if c['turn']==rec['turn'] and c['step']==0)
 text=(b/'run/calls'/f'{key[0]}-{key[1]}'/f"{rec['turn']}-0/thinking.txt").read_text();assert hashlib.sha256(text.encode()).hexdigest()==rec['thinkingSha256']
 p=b/'run/semantic-annotations'/rec['thinkingSha256']
 if rec['modelCalled']:
  req=json.loads((p/'request.json').read_text());data=json.loads(req['input'][0]['content'])
  assert set(data)=={'edges','needs','numberedLines'} and data['numberedLines']==[[i,line] for i,line in enumerate(text.splitlines(keepends=True))]
  assert req['instructions']==plan['semanticRubric'] and req['reasoning']=={'effort':'none'} and req['tools']==[plan['semanticTool']]
  term=json.loads((p/'response.json').read_text()).get('terminal') or {};u=term.get('usage')
  if rec['grossTokens'] is not None:assert rec['grossTokens']==u['input_tokens']+u['output_tokens']
 if not rec['failure']:
  tc=[x for x in term['output'] if x['type']=='function_call'];assert len(tc)==1
  payload=json.loads(tc[0]['arguments']);assert branch_semantic_validate(text,payload)==rec['lineProposals']
  accepted=[];rejected=[]
  for item in payload['episodes']:
   try:
    e=shared_validate_label(text,item,task,call['suppliedAtoms'],earlier);e.update(turn=call['turn'],step=0)
    old=[x for x in earlier if x['qualifiedPositive'] and x['atom']==e['atom']];e['crossBranchRepeat']=any(x['turn']!=call['turn'] for x in old)
    accepted.append(e);earlier.append(e)
   except Exception as error:rejected.append({'proposal':item,'failure':str(error)})
  assert accepted==rec['accepted'] and rejected==rec['rejected']
 summary.append({'case':rec['case'],'arm':rec['arm'],'turn':rec['turn'],'failure':rec['failure'],'accepted':len(rec['accepted']),'rejected':len(rec['rejected']),'lineProposals':len(rec['lineProposals']),'unresolvedLines':sum(x['category']=='unresolved' for x in rec['lineProposals']),'positiveEpisodes':sum(x['qualifiedPositive'] for x in rec['accepted']),'crossBranchPositiveRepeats':sum(x['crossBranchRepeat'] for x in rec['accepted']),'premiseUses':sum(x['category']=='premise_consumed' for x in rec['accepted']),'suppliedRederivations':sum(x.get('suppliedPremiseRederived',False) for x in rec['accepted'])})
assert sum(x['modelCalled'] for x in reviews)<=plan['maxSemanticCalls']
result={'passed':True,'lineClassesAreUnverifiedModelProposals':True,'scope':'Exact quote, stated premise and directed truth admission; not independent semantic rater/recall certification','knownTokens':sum(x['grossTokens'] or 0 for x in reviews),'unknownUsageCalls':sum(x['modelCalled'] and x['grossTokens'] is None for x in reviews),'reviews':summary}
(b/'run/semantic-audit.json').write_text(json.dumps(result,indent=2)+'\n');print('SEMANTIC_OFFLINE_ADMISSION_AUDIT_OK',len(summary),result['knownTokens'])
