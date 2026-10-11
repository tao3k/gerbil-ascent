"""Prospectively frozen range review of retained synthetic thinking; solver unchanged."""
import os,sys,json,hashlib,copy,inspect
from pathlib import Path
b=Path(sys.argv[1]).resolve();mode=sys.argv[2];sys.path[:0]=[str(b/'source/python/src'),str(b/'api' if (b/'api').exists() else b/'frozen/api-runtime')]
from ascent_test_support.evidence_chain_study import shared_check,shared_validate_label,SHARED_LABEL_TOOL,SHARED_RUBRIC,SEMANTIC_LINE_CATEGORIES
from ascent_test_support.model_study import provider
from ascent_test_support.movie_study import provider_key
plan=shared_check(b/'frozen');out=b/'run/range-review';rows=json.loads((b/'run/ledger.json').read_text());traces=[];calls=[]
for r in rows:
 for c in r['calls']:
  if c['step']!=0:continue
  text=(b/'run/calls'/f"{r['case']}-{r['arm']}"/f"{c['turn']}-0/thinking.txt").read_text()
  traces.append({'id':len(traces),'source':r['case'],'numberedLines':list(enumerate(text.splitlines(keepends=True)))})
  calls.append((r,c,text))
tool=copy.deepcopy(SHARED_LABEL_TOOL);episode=tool['parameters']['properties']['episodes']['items']
tool={'type':'function','name':'annotate_traces','description':'Blind semantic ranges and atomic path episodes for retained traces.',
      'parameters':{'type':'object','properties':{'traces':{'type':'array','items':{'type':'object','properties':{'id':{'type':'integer'},
      'lineRanges':{'type':'array','items':{'type':'object','properties':{'start':{'type':'integer'},'end':{'type':'integer'},'category':{'type':'string','enum':SEMANTIC_LINE_CATEGORIES}},'required':['start','end','category'],'additionalProperties':False}},
      'episodes':{'type':'array','items':episode}},'required':['id','lineRanges','episodes'],'additionalProperties':False}}},'required':['traces'],'additionalProperties':False}}
request={'model':plan['model'],'input':[{'role':'user','content':json.dumps({'sources':[{k:t[k] for k in ('edges','needs')} for t in plan['tasks']],'traces':traces},separators=(',',':'))}],
 'instructions':SHARED_RUBRIC+' Return every trace id exactly once. Replace per-line arrays with compact half-open lineRanges [start,end): start inclusive, end exclusive, with category premise_use, path_derivation, absence_argument, optimization, other or unresolved. Ranges must be ordered, gapless and cover line 0 through the exact numbered-line count; use optimization for long arithmetic/search sections and unresolved when unclear. Blank lines may inherit a surrounding section category. Do not output a category repeatedly per line. Line categories are proposals, not certified semantics. Atomic episodes should cover path/ready rederivation, absence recheck or use of an established path, including natural language with literal endpoints and stated premises. Do not emit arithmetic episodes; arithmetic remains a range category. Never invent graph premises absent from the quoted text. Do not assign arm, score or cost. These are retained independent traces; do not improve their answers.',
 'tools':[tool],'tool_choice':{'type':'function','name':'annotate_traces'},'reasoning':{'effort':'none'},'stream':True,'store':False,'max_output_tokens':16384}
def audit():
 term=json.loads((out/'response.json').read_text()).get('terminal') or {};u=term.get('usage');records=[];priors={};outputs={};failure=None
 try:
  assert term.get('status')=='completed','range annotation incomplete; no salvage'
  tc=[x for x in term.get('output',[]) if x['type']=='function_call'];assert len(tc)==1 and tc[0]['name']=='annotate_traces'
  payload=json.loads(tc[0]['arguments']);assert set(payload)=={'traces'}
  for x in payload['traces']:
   assert type(x.get('id')) is int and x['id'] not in outputs and 0<=x['id']<len(traces),'duplicate or unknown trace id'
   outputs[x['id']]=x
 except Exception as error:failure=str(error)
 for i,(r,c,text) in enumerate(calls):
  rec={'trace':i,'case':r['case'],'arm':r['arm'],'turn':c['turn'],'failure':failure,'lineRanges':[],'accepted':[],'rejected':[],'characters':len(text)};records.append(rec);prior=priors.setdefault((r['case'],r['arm']),[])
  if failure:continue
  try:
   x=outputs[i];assert set(x)=={'id','lineRanges','episodes'};n=len(traces[i]['numberedLines']);cursor=0
   for span in x['lineRanges']:
    assert set(span)=={'start','end','category'} and type(span['start']) is int and type(span['end']) is int
    assert span['start']==cursor and cursor<span['end']<=n and span['category'] in SEMANTIC_LINE_CATEGORIES,'invalid semantic range coverage'
    cursor=span['end']
   assert cursor==n,'semantic range coverage incomplete'
   rec['lineRanges']=x['lineRanges']
   end=0
   for item in x['episodes']:
    try:
     e=shared_validate_label(text,item,plan['tasks'][r['case']],c['suppliedAtoms'],prior)
     assert e['span'][0]>=end,'unordered or overlapping quote'
     old=[p for p in prior if p['qualifiedPositive'] and p['atom']==e['atom']];e.update(turn=c['turn'],crossBranchRepeat=any(p['turn']!=c['turn'] for p in old))
     rec['accepted'].append(e);prior.append(e);end=e['span'][1]
    except Exception as error:rec['rejected'].append({'proposal':item,'failure':str(error)})
  except Exception as error:rec['failure']=str(error)
 result={'prospectiveRangeRevision':True,'doesNotChangePriorCoverageFailure':True,'solverPlanSha256':hashlib.sha256((b/'frozen/plan.json').read_bytes()).hexdigest(),'lineClassesAreUnverifiedModelProposals':True,'usage':u,'knownTokens':u['input_tokens']+u['output_tokens'] if u else None,'records':records}
 return result
if mode=='prepare':
 out.mkdir(exist_ok=False);(out/'request.json').write_text(json.dumps(request,indent=2)+'\n')
 (out/'manifest.json').write_text(json.dumps({'maxProviderCalls':1,'requestSha256':hashlib.sha256((out/'request.json').read_bytes()).hexdigest(),'runnerSha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'solverPlanSha256':hashlib.sha256((b/'frozen/plan.json').read_bytes()).hexdigest(),'thinkingHashes':[hashlib.sha256(x[2].encode()).hexdigest() for x in calls],'purpose':'Prospective compact range review after failed full line arrays; no task/grader/solver budget changes; no previous annotation verdict overwritten'},indent=2)+'\n')
 print('RANGE_REVIEW_FROZEN',len(traces),len(json.dumps(request).encode()))
elif mode=='live':
 manifest=json.loads((out/'manifest.json').read_text());assert manifest['runnerSha256']==hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
 assert manifest['requestSha256']==hashlib.sha256((out/'request.json').read_bytes()).hexdigest();assert not (out/'response.json').exists()
 provider(json.loads((out/'request.json').read_text()),provider_key(),out/'response.json')
 result=audit();(out/'audit.json').write_text(json.dumps(result,indent=2)+'\n');print('RANGE_REVIEW_RESULT',[(r['trace'],r['failure'],len(r['accepted']),len(r['rejected'])) for r in result['records']])
elif mode=='audit':
 result=audit();assert result==json.loads((out/'audit.json').read_text());print('RANGE_REVIEW_OFFLINE_AUDIT_OK')
else:raise ValueError(mode)
