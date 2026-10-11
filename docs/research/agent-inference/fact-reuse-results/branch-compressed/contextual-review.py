"""Post-run analyst supplement; never changes the original failed review verdict."""
import sys,json,hashlib
from pathlib import Path
b=Path(sys.argv[1]).resolve();sys.path[:0]=[str(b/'source/python/src'),str(b/'api')]
from ascent_test_support.evidence_chain_study import shared_check,branch_semantic_blocks,SEMANTIC_BLOCK_TAGS,shared_validate_label
plan=shared_check(b/'frozen');out=b/'retained-review';rows=json.loads((out/'semantic-ledger.json').read_text());decisions={
 (0,'baseline',1):{0:['task_interpretation','positive_derivation','unclear'],1:['task_interpretation','positive_derivation','negative_argument','unclear'],2:['task_interpretation','positive_derivation','unclear'],
 4:['optimization'],5:['optimization'],6:['optimization'],8:['task_interpretation','unclear'],9:['task_interpretation','unclear'],10:['task_interpretation','unclear'],11:['task_interpretation','unclear'],12:['task_interpretation','unclear'],13:['task_interpretation','unclear'],16:['task_interpretation','unclear'],19:['optimization'],20:['optimization'],21:['optimization'],22:['optimization'],24:['optimization','unclear']},
 (1,'scheme',0):{3:['negative_fact_use','downstream_inference','optimization']}}
records=[];total=0;manual=0
for r in rows:
 key=(r['case'],r['arm'],r['turn']);text=(out/'calls'/f'{r["case"]}-{r["arm"]}'/f'{r["turn"]}-0'/'thinking.txt').read_text();blocks=branch_semantic_blocks(text,plan['semanticReviewBlockChars']);folder=out/'semantic-annotations'/r['thinkingSha256'];term=json.loads((folder/'response.json').read_text())['terminal'];assert term['status']=='completed';payload=json.loads(next(x for x in term['output'] if x['type']=='function_call')['arguments']);indexed={x['id']:x['tags'] for x in payload['blocks']};assert len(indexed)==len(blocks)
 review=[];bad=set()
 for block in blocks:
  tags=indexed[block['id']];valid=all(t in SEMANTIC_BLOCK_TAGS for t in tags)
  if not valid:
   bad.add(block['id']);tags=decisions[key][block['id']];manual+=len(block['text'])
  review.append({'id':block['id'],'span':block['span'],'quoteSha256':hashlib.sha256(block['text'].encode()).hexdigest(),
   'quote':block['text'] if not valid else None,'tags':tags,'reviewMethod':'manual contextual review' if not valid else 'individually valid model proposal',
   'independentSemanticGold':False,'negativeArgumentCompletenessVerified':False})
 assert bad==set(decisions.get(key,{})),(key,bad)
 total+=len(text);records.append({'case':r['case'],'arm':r['arm'],'turn':r['turn'],'originalFailure':r['failure'],
   'originalFullReviewVerdictUnchanged':True,'reviewedSections':review,'notReviewedCharacters':0,
   'unclearCharacters':sum(x['span'][1]-x['span'][0] for x in review if 'unclear' in x['tags']),
   'wholeTraceRepeatedDerivations':None,'fullSemanticRecallCertified':False})
# Analyst-authored reconstruction quotes from the failed baseline trace. They are
# independently checked, not rescued model labels or a changed original verdict.
r=next(r for r in rows if (r['case'],r['arm'],r['turn'])==(0,'baseline',1));text=(out/'calls/0-baseline/1-0/thinking.txt').read_text()
prior=[e for x in rows if (x['case'],x['arm'],x['turn'])==(0,'baseline',0) for e in x['accepted']]
quotes=[('Edges include [0,1],[1,2],[2,3],[3,4],[4,5] giving path 0 to5.',[['edge',0,1],['edge',1,2],['edge',2,3],['edge',3,4],['edge',4,5]]),
 ('[0,1],[1,2],[2,3],[3,4],[4,5] => path 0->5.',[['edge',0,1],['edge',1,2],['edge',2,3],['edge',3,4],['edge',4,5]]),
 ('[0,6],[6,7],[7,5] => path 0->7->5.',[['edge',0,6],['edge',6,7],['edge',7,5]])]
accepted=[]
for quote,premises in quotes:
 e=shared_validate_label(text,{'quote':quote,'occurrence':0,'category':'positive_derivation','atom':['path',0,5],'premises':premises},plan['tasks'][0],[],prior)
 e['crossBranchRepeat']=any(p['turn']!=1 for p in prior if p['qualifiedPositive'] and p['atom']==e['atom']);e['turn']=1
 accepted.append(e);prior.append(e)
# Directly review cached positive path reconstruction and negative recheck attempts.
ledger=json.loads((out/'ledger.json').read_text());call=next(c for row in ledger if (row['case'],row['arm'])==(0,'facts') for c in row['calls'] if c['turn']==1)
facts=[o['conclusion'] for o in call['entryEvidence']['observations']]
text=(out/'calls/0-facts/1-0/thinking.txt').read_text();fact_reconstructions=[]
for quote,atom,premises in [
 ('Path 0→5: 0→1→2→3→4→5 exists.', ['path',0,5],[['edge',0,1],['edge',1,2],['edge',2,3],['edge',3,4],['edge',4,5]]),
 ('Path 20→200: 20→100→200 exists.', ['path',20,200],[['edge',20,100],['edge',100,200]]),
 ('Item 1: [2,5] and [21,201]. 2→3→4→5 exists.', ['path',2,5],[['edge',2,3],['edge',3,4],['edge',4,5]]),
 ('21→101→201 exists.', ['path',21,201],[['edge',21,101],['edge',101,201]])]:
 e=shared_validate_label(text,{'quote':quote,'occurrence':0,'category':'positive_derivation','atom':atom,'premises':premises},plan['tasks'][0],call['suppliedAtoms'],[])
 assert e['suppliedPremiseRederived'] and not e['newConsequence'];fact_reconstructions.append(e)
negative_attempts=[]
rec=next(r for r in rows if (r['case'],r['arm'],r['turn'])==(0,'facts',1))
for e in rec['accepted']:
 if e['category']!='absence_recheck':continue
 assert any(f['atom']==e['atom'] and f['status']=='finite-absent' for f in facts)
 assert e['premises'] and all(p[0]=='edge' and p[1:] in plan['tasks'][0]['edges'] for p in e['premises'])
 negative_attempts.append({**e,'analystSemanticRole':'negative_rederivation_attempt','preexposedStatus':'finite-absent',
  'reason':'Explicit endpoint question followed by reversed edge reconstruction and an absence conclusion, after the native conclusion was already exposed.',
  'proofCompletenessVerified':False})
historical=json.loads((out/'historical-quote-probe.json').read_text())[0];assert historical['thinkingSha256']==rec['thinkingSha256']
ready_correction=[]
for e in historical['accepted']:
 if e.get('qualifiedPositive'):
  assert e['atom'][0]=='ready' and not e['suppliedPremiseRederived']
  ready_correction.append({'quote':e['quote'],'atom':e['atom'],'nativePathReconstruction':False,
    'semanticRole':'downstream item eligibility reasoning','catalogNewConsequence':e['newConsequence'],
    'chronologicallyNewToThinking':None,'scope':'New in the admitted catalog, not proof that it first occurs here in the thinking.'})
result={'scope':'Post-run unblinded analyst supplement of model block proposals; no original failed verdict repaired or exhaustive semantic recall certified.',
 'reviewedProposalCharacters':total,'manuallyReviewedCharacters':manual,'notReviewedCharacters':0,'wholeTraceRepeatedDerivations':None,
 'negativeRederivations':None,'fullSemanticRecallCertified':False,'sourceHead':plan['sourceState']['head'],
 'records':records,'analystAuthoredBaselineReconstructions':accepted,'analystAuthoredFactPositiveReconstructions':fact_reconstructions,'analystReviewedFactNegativeRecheckAttempts':negative_attempts,'historicalReadyInterpretationCorrection':ready_correction,
 'manualRationale':'Baseline blocks explore inconsistent task/start/direction interpretations or perform arithmetic; unclear content remains unclear. Scheme block 3 applies already-read native negative factors to eliminate group 2, then derives a group/weight distribution. It does not reconstruct any absent directed path. Native Fact use is distinguished from common task edges and numeric item fields.'}
p=out/'contextual-review.json'
if '--check' in sys.argv:assert json.loads(p.read_text())==result
else:p.write_text(json.dumps(result,indent=2)+'\n')
print('CONTEXTUAL_REVIEW_REPLAY_OK',total,'characters',manual,'manual','original failures',sum(r['failure'] is not None for r in rows),'manual cross-branch reconstructions',sum(e['crossBranchRepeat'] for e in accepted))
