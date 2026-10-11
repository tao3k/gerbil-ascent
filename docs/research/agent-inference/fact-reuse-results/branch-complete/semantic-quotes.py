"""Read-only exploratory quote projection; full range failure remains unchanged."""
import sys,json,hashlib
from pathlib import Path
b=Path(sys.argv[1]);sys.path[:0]=[str(b/'source/python/src'),str(b/'api' if (b/'api').exists() else b/'frozen/api-runtime')]
from ascent_test_support.evidence_chain_study import shared_check,shared_validate_label
plan=shared_check(b/'frozen');rows=json.loads((b/'run/ledger.json').read_text());previous=json.loads((b/'run/range-review/audit.json').read_text())
term=json.loads((b/'run/range-review/response.json').read_text()).get('terminal') or {};assert term['status']=='completed','No incomplete JSON salvage'
tc=[x for x in term['output'] if x['type']=='function_call'];assert len(tc)==1 and tc[0]['name']=='annotate_traces'
payload=json.loads(tc[0]['arguments']);assert set(payload)=={'traces'}
outputs={}
for x in payload['traces']:
 assert type(x.get('id')) is int and x['id'] not in outputs
 outputs[x['id']]=x
calls=[(r,c) for r in rows for c in r['calls'] if c['step']==0];assert set(outputs)==set(range(len(calls)))
prior={};records=[]
for i,(r,c) in enumerate(calls):
 text=(b/'run/calls'/f"{r['case']}-{r['arm']}"/f"{c['turn']}-0/thinking.txt").read_text();earlier=prior.setdefault((r['case'],r['arm']),[])
 record={'trace':i,'case':r['case'],'arm':r['arm'],'turn':c['turn'],'rawThinkingSha256':hashlib.sha256(text.encode()).hexdigest(),'originalRangeFailure':previous['records'][i]['failure'],'accepted':[],'rejected':[],'partition':[],'characters':len(text)};records.append(record)
 cursor=0
 for item in outputs[i]['episodes']:
  try:
   e=shared_validate_label(text,item,plan['tasks'][r['case']],c['suppliedAtoms'],earlier)
   assert e['span'][0]>=cursor,'overlapping or unordered proposal'
   old=[p for p in earlier if p['qualifiedPositive'] and p['atom']==e['atom']]
   e.update(turn=c['turn'],crossBranchRepeat=any(p['turn']!=c['turn'] for p in old))
   native=[o['conclusion'] for o in (c.get('entryEvidence') or {}).get('observations',[])]
   e['preexposedNativeStatus']=next((f['status'] for f in native if f['atom']==e['atom']),None)
   e['negativeUseOrRecheckUnresolved']=(e['category']=='absence_recheck' and e['preexposedNativeStatus']=='finite-absent')
   record['accepted'].append(e);earlier.append(e)
   a,z=e['span']
   if cursor<a:record['partition'].append({'span':[cursor,a],'category':'unreviewed_semantics'})
   record['partition'].append({'span':[a,z],'category':'admitted_atomic_proposal'});cursor=z
  except Exception as error:record['rejected'].append({'proposal':item,'failure':str(error)})
 if cursor<len(text):record['partition'].append({'span':[cursor,len(text)],'category':'unreviewed_semantics'})
 assert sum(p['span'][1]-p['span'][0] for p in record['partition'])==len(text)
result={'postRunExploratoryProjection':True,'originalCoverageVerdictUnchanged':True,'allUnmatchedCharactersExplicitlyUnreviewed':True,'scope':'Atomic exact-quote/stated-premise/directed-truth admission only. No claim of comprehensive semantics, causal cognition or independently rated annotation. Not a successful full-range review.','records':records}
(b/'run/semantic-quotes.json').write_text(json.dumps(result,indent=2)+'\n')
print('SEMANTIC_QUOTES_PROJECTED',[(r['trace'],len(r['accepted']),len(r['rejected'])) for r in records])
