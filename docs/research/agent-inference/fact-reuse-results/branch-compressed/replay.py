"""Offline exact-source/native/API/model receipt replay on the qualified host."""
import sys,os,json,hashlib,tarfile,shutil,tempfile,subprocess
from pathlib import Path
p=Path(__file__).resolve().parent
for name,digest in json.loads((p/'integrity.json').read_text()).items():
 assert hashlib.sha256((p/name).read_bytes()).hexdigest()==digest,name
b=Path(tempfile.mkdtemp(prefix='ascent-compressed-replay.')).resolve()
for name in ('qualification-raw.tar.gz','raw.tar.gz','retained-review-raw.tar.gz'):
 with tarfile.open(p/name) as t:t.extractall(b,filter='data')
# Reconstruct the actual committed producer, not a primary dirty workspace.
subprocess.run(['git','clone','--quiet','--branch','research/library-evidence-consumer',str(p/'source.bundle'),str(b/'source')],check=True)
plan=json.loads((b/'frozen/plan.json').read_text());assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=b/'source',text=True).strip()==plan['sourceState']['head']
env=os.environ.copy();env.pop('DEEPSEEK_API_KEY',None);env['PYTHONPATH']=str(b/'source/python/src')+':'+str(b/'frozen/api-runtime');env['GERBIL_PATH']=str(b/'gerbil')
(b/'preview').rename(b/'reference-preview')
subprocess.run([sys.executable,str(p/'preview-audit.py'),str(b)],env=env,check=True)
for f in (b/'reference-preview').glob('*.json'):assert f.read_bytes()==(b/'preview'/f.name).read_bytes(),f.name
module=[sys.executable,'-m','ascent_test_support.evidence_chain_study']
subprocess.run(module+['shared-committed-check',str(b/'frozen'),str(b/'offline-commit-gate')],cwd=b/'source',env=env,check=True)
subprocess.run(module+['branch-import-output-qualification',str(b/'frozen'),str(b/'output-qualification')],cwd=b/'source',env=env,check=True)
subprocess.run([sys.executable,str(p/'run-audit.py'),str(b)],env=env,check=True)
assert (b/'run/audit.json').read_bytes()==(p/'audit.json').read_bytes()
(b/'run/annotations').rename(b/'reference-annotations');(b/'run/annotation-ledger.json').rename(b/'reference-annotation-ledger.json')
subprocess.run(module+['shared-label',str(b/'frozen'),str(b/'run')],cwd=b/'source',env=env,check=True)
assert (b/'run/annotation-ledger.json').read_bytes()==(b/'reference-annotation-ledger.json').read_bytes()
for f in (b/'reference-annotations').iterdir():assert f.read_bytes()==(b/'run/annotations'/f.name).read_bytes()
subprocess.run(module+['branch-report',str(b/'frozen'),str(b/'run')],cwd=b/'source',env=env,check=True)
assert (b/'run/report.json').read_bytes()==(p/'report.json').read_bytes()
for mode,name in (('retained','retained-semantic-audit.json'),('new','semantic-audit.json')):
 subprocess.run([sys.executable,str(p/'semantic-audit.py'),str(b),mode],env=env,check=True)
 folder='retained-review' if mode=='retained' else 'run';assert (b/folder/'semantic-audit.json').read_bytes()==(p/name).read_bytes()
subprocess.run([sys.executable,str(p/'contextual-review.py'),str(b),'--check'],env=env,check=True)
assert (b/'retained-review/contextual-review.json').read_bytes()==(p/'retained-contextual-review.json').read_bytes()
subprocess.run([sys.executable,'-m','unittest','discover','-s',str(b/'source/python/tests'),'-p','test_shared_premise.py'],env=env,check=True)
print('COMPRESSED_EXACT_SOURCE_OFFLINE_REPLAY_OK: committed inputs, 36 native inputs, all solver costs/grades, literal annotations, both semantic audits, original failures and manual supplement')
print('REPLAY_RECEIPTS',b)
