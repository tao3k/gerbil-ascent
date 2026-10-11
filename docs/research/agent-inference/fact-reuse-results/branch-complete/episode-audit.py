"""Exploratory atomic admission from completed raw annotation proposals.
Never changes the frozen full-coverage verdict. No provider or repair calls.
"""
import sys,json,hashlib
from pathlib import Path
b=Path(sys.argv[1]);sys.path[:0]=[str(b/'source/python/src'),str(b/'api' if (b/'api').exists() else b/'frozen/api-runtime')]
from ascent_test_support.evidence_chain_study import shared_check,shared_validate_label
plan=shared_check(b/'frozen');rows=json.loads((b/'run/ledger.json').read_text());reviews=json.loads((b/'run/semantic-ledger.json').read_text());prior={};results=[]
for r in reviews:
 key=(r['case'],r['arm']);earlier=prior.setdefault(key,[])
 c=next(c for row in rows if (row['case'],row['arm'])==key for c in row['calls'] if c['turn']==r['turn'] and c['step']==0)
 text=(b/'run/calls'/f'{key[0]}-{key[1]}'/f"{r['turn']}-0/thinking.txt").read_text()
 rec={'case':key[0],'arm':key[1],'turn':r['turn'],'originalCoverageFailure':r['failure'],'accepted':[],'rejected':[],'unavailable':None,'thinkingSha256':hashlib.sha256(text.encode()).hexdigest()}
 try:
  assert r['modelCalled'],'not reviewed under frozen annotation call bound'
  term=json.loads((b/'run/semantic-annotations'/r['thinkingSha256']/'response.json').read_text()).get('terminal') or {}
  assert term.get('status')=='completed','incomplete annotation; no JSON salvage'
  calls=[x for x in term.get('output',[]) if x['type']=='function_call'];assert len(calls)==1 and calls[0]['name']=='annotate'
  payload=json.loads(calls[0]['arguments']);assert isinstance(payload.get('episodes'),list),'no atomic episode proposals'
  previous_end=0
  for item in payload['episodes']:
   try:
    e=shared_validate_label(text,item,plan['tasks'][key[0]],c['suppliedAtoms'],earlier)
    assert e['span'][0]>=previous_end,'overlapping or unordered episode'
    old=[x for x in earlier if x['qualifiedPositive'] and x['atom']==e['atom']]
    e.update(turn=c['turn'],crossBranchRepeat=any(x['turn']!=c['turn'] for x in old))
    rec['accepted'].append(e);earlier.append(e);previous_end=e['span'][1]
   except Exception as error:rec['rejected'].append({'proposal':item,'failure':str(error)})
 except Exception as error:rec['unavailable']=str(error)
 # Exact atomic coverage is separate from the failed model line classification.
 intervals=sorted(e['span'] for e in rec['accepted']);cursor=0;partition=[]
 for start,end in intervals:
  if cursor<start:partition.append({'span':[cursor,start],'category':'unreviewed_semantics'})
  partition.append({'span':[start,end],'category':'admitted_atomic_proposal'});cursor=end
 if cursor<len(text):partition.append({'span':[cursor,len(text)],'category':'unreviewed_semantics'})
 rec['characterPartition']=partition;rec['totalCharacters']=len(text);rec['admittedQuoteCharacters']=sum(e['span'][1]-e['span'][0] for e in rec['accepted'])
 assert sum(e['span'][1]-e['span'][0] for e in partition)==len(text)
 results.append(rec)
result={'exploratoryPostRunAudit':True,'fullCoverageFailureUnchanged':True,'scope':'Only individually admitted completed atomic proposals; all other characters remain unreviewed semantics. Not preregistered full semantic recall or successful full annotation. No independent arithmetic correctness claim.','results':results}
(b/'run/semantic-episode-audit.json').write_text(json.dumps(result,indent=2)+'\n')
print('ATOMIC_PROPOSAL_AUDIT_OK',[(r['case'],r['arm'],r['turn'],len(r['accepted']),len(r['rejected']),r['unavailable']) for r in results])
