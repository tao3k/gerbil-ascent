import sys,json,hashlib,shutil
from pathlib import Path
from ascent_engine.evidence import compact_observation,expand_observation
from ascent_test_support.evidence_chain_study import shared_truth,branch_semantic_partition,branch_semantic_summary
out=Path(sys.argv[1]);rows=json.loads((out/'ledger.json').read_text());plan=json.loads((out/'plan.json').read_text());reviews=[];projections=[]
markers={
('facts',0):('Let me look at conclusions.','So each item has two paths.','Required: item 0.'),
('facts',1):('Let me check the conclusions:','Now each item has two paths.','Now we must select four items'),
('scheme',0):('Evidence conclusions:','Now each item has two paths.','Branch: id 0'),
('scheme',1):('Each item has two paths.','So items whose paths','Now branch constraints:')}
for row in rows:
 for c in row['calls']:
  key=f"{row['case']}-{row['arm']}-{c['turn']}-{c['step']}"
  text=(out/'thinking'/f'{key}.txt').read_text();assert hashlib.sha256(text.encode()).hexdigest()==c['thinkingSha256']
  segments=[]
  if row['case']==1 and (row['arm'],c['turn']) in markers:
   start,middle,end=markers[row['arm'],c['turn']];a=text.index(start);b=text.index(middle,a);z=text.index(end,b)
   facts=[o['conclusion'] for o in c['entryEvidence']['observations']]
   for f in facts:assert shared_truth(plan['tasks'][1],f['atom'])==f['present']
   for x,y,kind in ((a,b,'positive_and_negative_fact_read'),(b,z,'new_downstream_item_feasibility')):
    segments.append({'span':[x,y],'quote':text[x:y],'category':kind,
      'reviewMethod':'manual contextual review, post-run exploratory; not independent semantic gold',
      'positiveFacts':[f['atom'] for f in facts if f['status']=='verified'],
      'negativeFacts':[f['atom'] for f in facts if f['status']=='finite-absent'],
      'pathProofReconstructionObserved':False,'negativeProofReconstructionObserved':False,
      'scope':'Only this quoted section; reading facts and applying item conjunctions is not path rederivation.'})
  partition=branch_semantic_partition(text,segments)
  reviews.append({'key':key,'thinkingSha256':c['thinkingSha256'],'characters':len(text),
   'reviewedSections':segments,'unreviewedCharacters':sum(p['span'][1]-p['span'][0] for p in partition if p['category']=='unreviewed_semantics'),
   'wholeTraceRepeatedDerivations':None,'wholeTraceNewInferences':None,'negativeRederivations':None,'fullSemanticRecallCertified':False,
   'providerFailure':c['failure'],'outputTruncated':c.get('outputTruncated',False)})
  if c.get('entryEvidence'):
   p=c['entryEvidence'];request=json.loads((out/'requests'/f'{key}.json').read_text());old=json.loads(request['input'][0]['content'])['nativeEvidence'];new=compact_observation(p);assert expand_observation(old)==p and expand_observation(new)==p
   encode=lambda x:len(json.dumps(x,separators=(',',':')).encode())
   projections.append({'key':key,'oldBytes':encode(old),'newBytes':encode(new),'roundTrip':True,
      'nativeNodes':len(p.get('supportNodes',[])),'nativeObservations':len(p['observations'])})
source1={r['arm']:r for r in rows if r['case']==1}
def totals(arm):
 cs=source1[arm]['calls'];return {'input':sum(c['usage']['input_tokens'] for c in cs),'allOutput':sum(c['usage']['output_tokens'] for c in cs),
 'firstTwoOutput':sum(c['usage']['output_tokens'] for c in cs[:2]),'calls':len(cs),
 'reasoning':sum(c['usage']['output_tokens_details']['reasoning_tokens'] for c in cs)}
atomic=json.loads((out/'prior-atomic-proposals.json').read_text())
proposal_summaries=[]
for record in atomic['records']:
 key=f"{record['case']}-{record['arm']}-{record['turn']}-0"
 text=(out/'thinking'/f'{key}.txt').read_text()
 assert hashlib.sha256(text.encode()).hexdigest()==record['rawThinkingSha256']
 proposal_summaries.append({'key':key,**branch_semantic_summary(text,record['accepted'])})
result={'atomicProposalSummaries':proposal_summaries,'source1':{a:totals(a) for a in ('facts','scheme')},'reviews':reviews,'projectionChecks':projections,
 'externalCalls':0,'solverRerun':False,'tasksAndJudgeUnchanged':True,'wholeTraceRepeatedDerivations':None,
 'source1FirstTwoAdditionalSchemeInput':2290,'source1FirstTwoAdditionalSchemeAllOutput':1579,
 'inputTokensAfterProjection':None,'qualityAfterProjection':None,'unusedBudgetIsSavings':False}
rendered=json.dumps(result,indent=2)+'\n'
if '--check' in sys.argv:
 assert (out/'review.json').read_text()==rendered, 'review receipt changed'
else:
 (out/'review.json').write_text(rendered)
print(json.dumps({k:v for k,v in result.items() if k not in ('reviews','projectionChecks','atomicProposalSummaries')},indent=2))
print('REPLAY_OK',len(reviews),'traces',len(projections),'lossless native packets',sum(len(r['reviewedSections']) for r in reviews),'manual sections')
print('PROJECTION',[(p['key'],p['oldBytes'],p['newBytes']) for p in projections[:4]])
