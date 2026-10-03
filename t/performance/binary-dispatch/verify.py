"""Audit the final source, native artifacts, raw statistics and test receipts."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
root=Path(__file__).resolve().parent
repository=root.parents[2]
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
spec=importlib.util.spec_from_file_location('performance',repository/'tools/performance_execution.py')
runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)
qualified=json.loads((root/'qualified.json').read_text())
assert all(digest(repository/p)==h for p,h in qualified['sources'].items())
assert all(digest(Path(p))==h for p,h in qualified['artifacts'].items())
snapshot=json.loads((root/'production-snapshot.json').read_text())
assert os.environ['GERBIL_PATH']==snapshot['gerbil_path']
runner.verify(snapshot)
lib=Path(os.environ['GERBIL_PATH'])/'lib'
dependencies={str(p):digest(p) for p in sorted(lib.rglob('*')) if p.is_file()
    and 'gerbil-ascent' not in p.relative_to(lib).parts
    and (p.suffix in ('.ssi','.so','.a','.o') or re.search(r'\.o\d+$',p.name))}
assert dependencies==json.loads((root/'native-dependencies.json').read_text())
subprocess.run(['python3',str(root/'report.py')],cwd=repository,check=True)
report=json.loads((root/'report.json').read_text())
assert sum(r['timing_qualified'] for r in report['results'])==11
assert all(r['control_within_ten_percent'] for r in report['results'] if r['control'])
gates=json.loads((root/'gates.json').read_text())
assert len(gates)==5 and all(r['exit']==0 for r in gates)
for row in gates:
    text=(root/(row['name']+'.log')).read_text()
    assert not re.search(r'ERROR (CASE|MODULE|HARNESS|CHECK)|Heap overflow|Stack overflow',text)
    if row['name']=='policy': assert 'COMPLETE findings=0 errors=0' in text
    else:
        assert 'CASE-OK ' in text and 'MODULE-OK ' in text and 'HARNESS-OK' in text and re.search(r'^OK$',text,re.M)
coverage=json.loads((root/'suite-coverage.json').read_text())
assert coverage['modules']==48 and coverage['cases']==376
for row in coverage['coverage']:
    text=(root/'modules'/Path(row['module']).with_suffix('.log').name).read_text()
    assert len(re.findall(r'^CASE-OK ',text,re.M))==row['count']
    assert len(re.findall(r'^CASE ',text,re.M))==row['count']
    assert 'MODULE-OK '+row['module'] in text and 'HARNESS-OK' in text and re.search(r'^OK$',text,re.M)
    assert not re.search(r'ERROR (CASE|MODULE|HARNESS|CHECK)|Heap overflow|Stack overflow',text)
programs=['core/binary-program.ss','table/expression.ss','t/qualification/ascent-binary-program-test.ss']
paths=[*programs,*[str(p.relative_to(repository)) for p in root.iterdir()
    if p.is_file() and (p.suffix in ('.py','.ss') or p.name in ('README.md','criteria.json','baseline.txt'))]]
(root/'final-audit.json').write_text(json.dumps(dict(
    source_sha256={p:digest(repository/p) for p in sorted(paths)},
    production_git_blobs={p:subprocess.check_output(['git','hash-object',p],cwd=repository,text=True).strip() for p in programs},
    matched_sources_and_artifacts_verified=True,production_sources_and_artifacts_verified=True,
    external_native_dependencies_verified=len(dependencies),matched_profiles=18,timing_qualified_profiles=11,
    controls_within_bound=True,allocation_claim=False,gates=gates,modules=48,cases=376,
    remote_ci_verified=False),indent=2)+'\n')
print('FINAL-AUDIT-OK 48 modules 376 Cases; 4 performance gates; 18 paired profiles')
