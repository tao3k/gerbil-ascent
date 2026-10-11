"""Offline replay of code-owned block review, quoted episodes and their failures."""
import sys,json,hashlib
from pathlib import Path
b=Path(sys.argv[1]).resolve();mode=sys.argv[2];sys.path[:0]=[str(b/'source/python/src'),str(b/'api' if (b/'api').exists() else b/'frozen/api-runtime')]
from ascent_test_support.evidence_chain_study import shared_check,shared_validate_label,branch_semantic_blocks,branch_semantic_block_admit,branch_semantic_partition,branch_semantic_summary
plan=shared_check(b/'frozen');out=b/('retained-review' if mode=='retained' else 'run');rows=json.loads((out/'ledger.json').read_text());records=json.loads((out/'semantic-ledger.json').read_text());bykey={(r['case'],r['arm'],r['turn']):r for r in records};priors={};summaries=[];known=0;unknown=0
for row in rows:
 prior=priors.setdefault((row['case'],row['arm']),[])
 for c in row['calls']:
  if c['step']!=0:continue
  rec=bykey[(row['case'],row['arm'],c['turn'])];text=(out/'calls'/f"{row['case']}-{row['arm']}"/f"{c['turn']}-0"/'thinking.txt').read_text();h=hashlib.sha256(text.encode()).hexdigest();assert h==rec['thinkingSha256']==c['thinkingSha256']
  folder=out/'semantic-annotations'/h;req=json.loads((folder/'request.json').read_text());data=json.loads(req['input'][0]['content']);blocks=branch_semantic_blocks(text,plan['semanticReviewBlockChars']);task=plan['tasks'][row['case']]
  assert data=={'edges':task['edges'],'needs':task['needs'],'reasoningBlocks':[{'id':x['id'],'text':x['text']} for x in blocks],'earlierConclusions':[o['conclusion'] for o in (c.get('entryEvidence') or {}).get('observations',[])]}
  assert req['instructions']==plan['semanticRubric'] and req['tools']==[plan['semanticTool']] and req['max_output_tokens']==plan['semanticOutputCap'] and req['reasoning']=={'effort':'none'}
  meta=json.loads((folder/'response.json').read_text());term=meta.get('terminal') or {};usage=term.get('usage');expected_failure=None;accepted=[];rejected=[];blockreviews=None
  if usage:assert rec['grossTokens']==usage['input_tokens']+usage['output_tokens'];known+=rec['grossTokens']
  else:unknown+=1
  try:
   assert not meta.get('error') and term.get('status')=='completed','semantic provider incomplete or failed'
   tc=[x for x in term.get('output',[]) if x.get('type')=='function_call'];assert len(tc)==1 and tc[0]['name']=='annotate','semantic submission shape'
   payload=json.loads(tc[0]['arguments']);assert set(payload)=={'episodes','blocks'} and isinstance(payload['episodes'],list),'semantic quote schema'
   blockreviews=branch_semantic_block_admit(blocks,payload['blocks'])
   for item in payload['episodes']:
    try:
     e=shared_validate_label(text,item,task,c['suppliedAtoms'],prior,supplied_absent=[o['conclusion']['atom'] for o in (c.get('entryEvidence') or {}).get('observations',[]) if o['conclusion']['status']=='finite-absent']);e.update(turn=c['turn'],step=c['step']);e['crossBranchRepeat']=any(x['turn']!=c['turn'] for x in prior if x['qualifiedPositive'] and x['atom']==e['atom'])
     assert not accepted or e['span'][0]>=accepted[-1]['span'][1],'overlapping or unordered quote'
     accepted.append(e);prior.append(e)
    except Exception as error:rejected.append({'proposal':item,'failure':str(error)})
  except Exception as error:expected_failure=str(error)
  assert rec['failure']==expected_failure and rec['accepted']==accepted and rec['rejected']==rejected
  assert rec['reviewProposalCoverageComplete']==(blockreviews is not None)
  if blockreviews is not None:assert rec['blockReviews']==blockreviews
  assert rec['characterPartition']==branch_semantic_partition(text,accepted) and rec['semanticSummary']==branch_semantic_summary(text,accepted)
  assert rec['fullSemanticRecallCertified'] is False
  tags={}
  for x in blockreviews or []:
   for t in x['tags']:tags[t]=tags.get(t,0)+1
  summaries.append({'case':row['case'],'arm':row['arm'],'turn':c['turn'],'characters':len(text),
   'reviewedProposalCharacters':len(text) if blockreviews is not None else 0,'unclearBlockCharacters':rec.get('unclearBlockCharacters'),
   'unreviewedCharacters':rec['notReviewedByBlockProposalsCharacters'],'blockTags':tags,'acceptedEpisodes':len(accepted),'rejectedEpisodes':len(rejected),
   'positiveFactUses':sum(e['category']=='premise_consumed' for e in accepted),'negativeFactUses':sum(e['category']=='absent_premise_consumed' for e in accepted),
   'positiveReconstructions':sum(e.get('qualifiedPositive',False) and e.get('suppliedPremiseRederived',False) for e in accepted),
   'crossBranchPositiveRepeats':sum(e.get('qualifiedPositive',False) and e.get('crossBranchRepeat',False) for e in accepted),
   'newPositiveInferences':sum(e.get('qualifiedPositive',False) and e.get('newConsequence',False) for e in accepted),
   'negativeStatementsUnresolved':sum(e['category']=='absence_recheck' for e in accepted),
   'wholeTraceRepeatedDerivations':None,'failure':expected_failure})
result={'offlineReplayPassed':True,'sourceHead':plan['sourceState']['head'],'scope':'Model block review proposals and exact-quote admission, not independent semantic gold or exhaustive recall.',
 'calls':len(records),'knownTokens':known,'unknownUsageCalls':unknown,'fullSemanticRecallCertified':False,'wholeTraceRepeatedDerivations':None,'records':summaries}
p=out/'semantic-audit.json'
if p.exists():assert json.loads(p.read_text())==result
else:p.write_text(json.dumps(result,indent=2)+'\n')
print('SEMANTIC_AUDIT_OK',len(records),'reviewed',sum(s['reviewedProposalCharacters'] for s in summaries),'of',sum(s['characters'] for s in summaries),'characters','failed',sum(s['failure'] is not None for s in summaries),'tokens',known)
