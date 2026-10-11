"""Local archived-API replay. Python 3.13+cffi and the qualified Darwin host.
No provider or key lookup. For a source rebuild use reproduce-clean.sh instead.
"""
import sys,os,shutil,tarfile,tempfile,json,hashlib,subprocess
from pathlib import Path
published=Path(__file__).resolve().parent
for name,digest in json.loads((published/'integrity.json').read_text()).items():
 assert hashlib.sha256((published/name).read_bytes()).hexdigest()==digest,name
work=Path(tempfile.mkdtemp(prefix='ascent-entry-replay.')).resolve()
print('Retained replay directory:',work,flush=True)
with tarfile.open(published/'qualification-raw.tar.gz') as archive:archive.extractall(work,filter='data')
with tarfile.open(published/'raw.tar.gz') as archive:archive.extractall(work,filter='data')
shutil.copytree(work/'frozen/inputs',work/'source');(work/'preview').rename(work/'reference-preview')
env=os.environ.copy();env.pop('DEEPSEEK_API_KEY',None);env['PYTHONPATH']=str(work/'source/python/src')+':'+str(work/'frozen/api-runtime');env['GERBIL_PATH']=str(work/'gerbil')
subprocess.run([sys.executable,str(published/'preview-audit.py'),str(work)],env=env,check=True)
for file in (work/'reference-preview').glob('*.json'):
 assert file.read_bytes()==(work/'preview'/file.name).read_bytes(),'native preview drift '+file.name
subprocess.run([sys.executable,str(published/'coverage-audit.py'),str(work)],env=env,check=True)
subprocess.run([sys.executable,str(published/'run-audit.py'),str(work)],env=env,check=True)
assert (work/'run/audit.json').read_bytes()==(published/'audit.json').read_bytes()
(work/'run/annotations').rename(work/'reference-annotations')
(work/'run/annotation-ledger.json').rename(work/'reference-annotation-ledger.json')
module=[sys.executable,'-m','ascent_test_support.evidence_chain_study']
subprocess.run(module+['shared-label',str(work/'frozen'),str(work/'run')],env=env,cwd=work/'source',check=True)
assert (work/'run/annotation-ledger.json').read_bytes()==(work/'reference-annotation-ledger.json').read_bytes()
for f in (work/'reference-annotations').iterdir():assert f.read_bytes()==(work/'run/annotations'/f.name).read_bytes(),f.name
subprocess.run(module+['branch-report',str(work/'frozen'),str(work/'run')],env=env,cwd=work/'source',check=True)
assert (work/'run/report.json').read_bytes()==(published/'report.json').read_bytes()
print('BRANCH_ENTRY_OFFLINE_REPLAY_OK: native requests, calibration, all model costs/scores, all literal annotations and final report match')
