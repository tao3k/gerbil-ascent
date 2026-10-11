"""Offline current annotation-contract receipt replay; no model/key lookup."""
import sys,os,json,tarfile,tempfile,shutil,subprocess,hashlib
from pathlib import Path
p=Path(__file__).resolve().parent;b=Path(tempfile.mkdtemp(prefix='ascent-quote-contract-replay.')).resolve()
with tarfile.open(p/'qualification-and-probe.tar.gz') as a:a.extractall(b,filter='data')
shutil.copytree(b/'frozen/inputs',b/'source')
code=r'''
import sys,json,hashlib
from pathlib import Path
from ascent_test_support.evidence_chain_study import shared_check,shared_validate_label,branch_semantic_partition
b=Path(sys.argv[1]);plan=shared_check(b/'frozen');rows=json.loads((b/'quote-probe/ledger.json').read_text());rec=json.loads((b/'quote-probe/semantic-ledger.json').read_text())[0];c=rows[0]['calls'][0];task=plan['tasks'][0]
text=(b/'quote-probe/calls/0-facts/1-0/thinking.txt').read_text();assert hashlib.sha256(text.encode()).hexdigest()==c['thinkingSha256']
out=b/'quote-probe/semantic-annotations'/rec['thinkingSha256'];req=json.loads((out/'request.json').read_text());data=json.loads(req['input'][0]['content']);assert set(data)=={'edges','needs','reasoningText','earlierConclusions'}
assert data['reasoningText']==text and data['earlierConclusions']==[o['conclusion'] for o in c['entryEvidence']['observations']]
assert req['instructions']==plan['semanticRubric'] and req['tools']==[plan['semanticTool']]
t=json.loads((out/'response.json').read_text())['terminal'];assert t['status']=='completed';tc=[x for x in t['output'] if x['type']=='function_call'];assert len(tc)==1;payload=json.loads(tc[0]['arguments']);assert set(payload)=={'episodes'}
assert rec['grossTokens']==t['usage']['input_tokens']+t['usage']['output_tokens'];accepted=[];rejected=[];prior=[]
for item in payload['episodes']:
 try:
  e=shared_validate_label(text,item,task,c['suppliedAtoms'],prior,supplied_absent=[o['conclusion']['atom'] for o in c['entryEvidence']['observations'] if o['conclusion']['status']=='finite-absent']);e.update(turn=1,step=0)
  old=[x for x in prior if x['qualifiedPositive'] and x['atom']==e['atom']];e['crossBranchRepeat']=any(x['turn']!=1 for x in old)
  assert not accepted or e['span'][0]>=accepted[-1]['span'][1],'overlapping or unordered quote'
  accepted.append(e);prior.append(e)
 except Exception as error:rejected.append({'proposal':item,'failure':str(error)})
assert accepted==rec['accepted'] and rejected==rec['rejected']
assert branch_semantic_partition(text,accepted)==rec['characterPartition']
assert rec['fullSemanticRecallCertified'] is False
print('QUOTE_CONTRACT_OFFLINE_REPLAY_OK',len(accepted),len(rejected),rec['unreviewedCharacters'])
'''
env=os.environ.copy();env.pop('DEEPSEEK_API_KEY',None);env['PYTHONPATH']=str(b/'source/python/src')+':'+str(b/'frozen/api-runtime');env['GERBIL_PATH']=str(b/'gerbil')
subprocess.run([sys.executable,'-c',code,str(b)],env=env,check=True)
print('Replay receipts:',b)
