"""Reconstruct the exact preceding evaluator, with only relocation and alpha renames."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
root=Path(__file__).resolve().parent
commit=(root/'baseline.txt').read_text().strip()
def original(path):return subprocess.check_output(['git','show',commit+':'+path],text=True)
source=original('program/evaluate.ss')
expected=re.sub(r'"([a-z-]+)\.ss"',r':gerbil-ascent/program/\1',source)
expected=expected.replace('gerbil-ascent-evaluate-program','ascent-result-reference-evaluate-program').replace('gerbil-ascent-make-engine','ascent-result-reference-make-engine')
reference=Path('t/qualification/ascent-result-reference-evaluate.ss').read_text()
assert expected==reference
shared=['program/positive.ss','program/analysis.ss','program/session.ss','table/access.ss','table/funs.ss','table/storage.ss']
scenarios=['ascent-session-update','ascent-ten-thousand-appends',
           'ascent-nonpositive-session-update','ascent-product-session']
shared += ['t/scenarios/performance/'+name+'/'+file for name in scenarios
           for file in ('scenario.ss','benchmark.ss')]
shared += ['t/performance/ascent-ss-profile.ss',
           't/performance/ascent-scenario-performance-test.ss']
for path in shared:assert Path(path).read_text()==original(path),path
(root/'reference-verification.json').write_text(json.dumps(dict(commit=commit,verified=True,
 source_sha256=hashlib.sha256(source.encode()).hexdigest(),
 reference_sha256=hashlib.sha256(reference.encode()).hexdigest(),
 adaptations=['relative program imports relocated','two exported evaluator names alpha renamed'],
 unchanged_shared=shared),indent=2)+'\n')
print('reference verified',commit)
