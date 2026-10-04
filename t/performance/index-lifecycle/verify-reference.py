"""Reconstruct the frozen reference from its recorded commit and adaptations."""
import hashlib
import json
import re
import subprocess
from pathlib import Path
root = Path(__file__).resolve().parent
commit = (root/'baseline.txt').read_text().strip()
def original(path):
    return subprocess.check_output(['git','show',commit+':'+path],text=True)
def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()
reference = Path('t/qualification')
source = original('table/funs.ss')
assert (reference/'ascent-index-reference-funs.ss').read_text() == source
provider = original('table/provider.ss').replace('"funs.ss"', ':gerbil-ascent/t/qualification/ascent-index-reference-funs').replace('gerbil-ascent-hash-index-provider','ascent-index-reference-hash-index-provider')
assert (reference/'ascent-index-reference-provider.ss').read_text() == provider
original_evaluator = original('program/evaluate.ss')
evaluator = re.sub(r'"([a-z-]+)\.ss"',r':gerbil-ascent/program/\1',original_evaluator)
evaluator = evaluator.replace('gerbil-ascent-evaluate-program','ascent-index-reference-evaluate-program').replace('gerbil-ascent-make-engine','ascent-index-reference-make-engine')
actual = (reference/'ascent-index-reference-evaluate.ss').read_text()
a = actual.index('(import (only-in :gerbil-ascent/t/qualification/ascent-index-reference-provider')
b = actual.index('(export ascent-index-reference',a)
adaptation = actual[a:b]
assert adaptation.count('(def ') == 2
assert 'reference-provider-build' in adaptation and 'reference-provider-extend!' in adaptation
assert 'gerbil-ascent-index-provider-build' in adaptation and 'gerbil-ascent-index-provider-extend!' in adaptation
evaluator = evaluator.replace('(export ascent-index-reference',adaptation+'(export ascent-index-reference',1)
evaluator = evaluator.replace('(let (built (gerbil-ascent-index-provider-build','(let (built (reference-provider-build').replace('(gerbil-ascent-index-provider-extend!\n                            provider','(reference-provider-extend!\n                            provider')
assert actual == evaluator
for shared in ('program/positive.ss','program/analysis.ss','table/provider.ss'):
    assert Path(shared).read_text() == original(shared), shared
result = dict(commit=commit, verified=True, source_hashes={
    'table/funs.ss':digest(source), 'table/provider.ss':digest(original('table/provider.ss')),
    'program/evaluate.ss':digest(original_evaluator)},
    reference_hashes={p.name:digest(p.read_text()) for p in reference.glob('ascent-index-reference-*.ss')},
    adaptations=['evaluator relative imports relocated and two exports alpha renamed',
                 'canonical default build/extend redirected to frozen provider through original generic dispatch',
                 'provider default export alpha renamed and algorithm import relocated'],
    boundary='Physical built-in algorithms are frozen; common analysis and positive execution remain unchanged. Custom receivers delegate to their original slots.')
(root/'reference-verification.json').write_text(json.dumps(result,indent=2)+'\n')
print('reference verified',commit)
