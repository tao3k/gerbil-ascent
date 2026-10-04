"""Collect every original gate independently on one verified compiled snapshot."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

root = Path(__file__).resolve().parent
script = Path('tools/performance_execution.py').resolve()
spec = importlib.util.spec_from_file_location('performance', script)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
environment = os.environ.copy()
runner.prepare(environment)
snapshot = json.loads(Path(environment['ASCENT_PERFORMANCE_SNAPSHOT']).read_text())
(root/'final-snapshot.json').write_text(json.dumps(snapshot, indent=2)+'\n')
resolution = Path(snapshot['library']).parent/'resolution.log'
(root/'final-resolution.log').write_text(resolution.read_text())
results = []

def collect(name, command):
    print('[native-qualification] START '+name, flush=True)
    runner.verify(snapshot)
    start=time.monotonic()
    with (root/(name+'.log')).open('w') as output:
        child=subprocess.Popen(command, cwd=runner.ROOT, env=environment,
            pass_fds=(int(environment['ASCENT_TEST_EXCLUSIVE_FD']),),
            stdout=output, stderr=subprocess.STDOUT)
        while True:
            try:
                status=child.wait(timeout=5);break
            except subprocess.TimeoutExpired:
                print('[native-qualification] RUNNING '+name, flush=True)
    runner.verify(snapshot)
    results.append(dict(name=name,exit=status,seconds=time.monotonic()-start))
    (root/'summary.json').write_text(json.dumps(results,indent=2)+'\n')
    print(results[-1],flush=True)

names=['ascent-byods-trrel','ascent-session-update','ascent-ten-thousand-appends',
       'ascent-nonpositive-session-update','ascent-rule-clauses','ascent-var-points-to',
       'ascent-upstream-examples','ascent-product-session','ascent-mutual-recursive-heads',
       'ascent-derived-aggregate','ascent-indexed-joins','ascent-byods-eqrel',
       'ascent-binary-program','ascent-reachability-closure','ascent-table-expression',
       'ascent-table-expression-membership','ascent-shortest-candidates']
for name in names:
    collect(name,['just','performance-scenario',name])
for name in ('complete-first','complete-repeat'):
    environment['ASCENT_COMPLETE_RECEIPT']=str(root/(name+'.sexp'))
    collect(name,['timeout','90s','gxi','-:max-heap=1G,debug=q',str(root/'complete-append.ss')])
raise SystemExit(int(any(x['exit'] for x in results)))
