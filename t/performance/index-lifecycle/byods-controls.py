"""Resolve both engines natively and compare the unchanged BYODS SS scenario."""
import json
import os
from pathlib import Path
import re
import subprocess
import time
root=Path(__file__).resolve().parent
repo=Path.cwd()
results=[]
for name in ('baseline','current'):
    environment=os.environ.copy()
    environment['GERBIL_LOADPATH']=str(repo/'.gerbil/index-lifecycle/lib')+':'+str(repo)
    environment['ASCENT_SS_SCENARIO']=str(root/(name+'-byods-scenario.ss'))
    command=['python3','tools/test_execution.py','run','--','timeout','120s','gerbil','-:max-heap=1G,debug=q','test','-v','5','t/performance/ascent-scenario-performance-test.ss']
    print('[byods-control] START '+name,flush=True)
    start=time.monotonic()
    with (root/(name+'-byods.log')).open('w') as output:
        child=subprocess.Popen(command,stdout=output,stderr=subprocess.STDOUT,env=environment)
        while True:
            try:
                status=child.wait(timeout=5);break
            except subprocess.TimeoutExpired:
                print('[byods-control] RUNNING '+name,flush=True)
    text=(root/(name+'-byods.log')).read_text()
    resolved=re.findall(r'^ENGINE-PATH (.+)$',text,re.M)
    assert len(resolved)==1 and '/.gerbil/index-lifecycle/lib/' in resolved[0] and resolved[0].endswith('.ssi'),resolved
    passed=(status==0 and 'CASE-OK bounded scenario' in text and
            'MODULE-OK t/performance/ascent-scenario-performance-test.ss' in text and
            'HARNESS-OK' in text and re.search(r'^OK$',text,re.M) and
            not re.search(r'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow',text))
    results.append(dict(name=name,exit=status,passed=bool(passed),seconds=time.monotonic()-start,
                        resolved_engine=resolved[0],
                        receipts=re.findall(r'^\[gerbil-ascent-benchmark\].+$',text,re.M),
                        failed_p95_ns=[int(v) for v in re.findall(r'\(p95Ns \. (\d+)\)',text)]))
    (root/'byods-controls.json').write_text(json.dumps(results,indent=2)+'\n')
    print(results[-1],flush=True)
raise SystemExit(int(any(not r['passed'] for r in results)))
