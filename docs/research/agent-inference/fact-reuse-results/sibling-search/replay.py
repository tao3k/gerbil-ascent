"""Offline receipt replay. Run with Python 3.13 and cffi installed; no model calls.
The archived native API is Darwin/architecture specific. Use reproduce-clean.sh
for a source rebuild instead of relying on this receipt's binaries.
"""
import hashlib,json,os,shutil,subprocess,sys,tarfile,tempfile
from pathlib import Path
published=Path(__file__).resolve().parent
for name,digest in json.loads((published/'integrity.json').read_text()).items():
    assert hashlib.sha256((published/name).read_bytes()).hexdigest()==digest,name
work=Path(tempfile.mkdtemp(prefix='ascent-sibling-replay.')).resolve()
print('Retained replay directory:',work,flush=True)
with tarfile.open(published/'raw.tar.gz') as archive:
    archive.extractall(work,filter='data')
root=work/'source';shutil.copytree(work/'frozen/inputs',root)
env=os.environ.copy();env['PYTHONPATH']=str(root/'python/src')+':'+str(work/'frozen/api-runtime')
env.pop('DEEPSEEK_API_KEY',None)
subprocess.run([sys.executable,str(published/'audit.py'),str(root)],env=env,cwd=root,check=True)
subprocess.run([sys.executable,'-m','ascent_test_support.evidence_chain_study','branch-report',str(work/'frozen'),str(work/'run')],env=env,cwd=root,check=True)
assert (work/'run/report.json').read_bytes()==(published/'report.json').read_bytes(),'report drift'
assert (work/'run/audit.json').read_bytes()==(published/'audit.json').read_bytes(),'audit drift'
print('OFFLINE_REPLAY_OK: source/API identities, protocol, budget, grader and report match')
