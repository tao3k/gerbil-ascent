"""Continue all unexecuted unchanged SS entries after a retained initial failure."""
import json
import subprocess
import time
from pathlib import Path
root=Path(__file__).resolve().parent/'remaining-ss'
root.mkdir(exist_ok=True)
names=['ascent-session-update','ascent-ten-thousand-appends','ascent-nonpositive-session-update','ascent-rule-clauses','ascent-var-points-to','ascent-upstream-examples','ascent-product-session','ascent-mutual-recursive-heads','ascent-derived-aggregate','ascent-indexed-joins','ascent-byods-eqrel','ascent-binary-program','ascent-reachability-closure','ascent-table-expression','ascent-table-expression-membership','ascent-shortest-candidates']
results=[]
for name in names:
    command=['just','performance-scenario',name]
    if name in ('ascent-binary-program','ascent-shortest-candidates'):
        command=['just','test-file','t/performance/'+name+'-performance-test.ss']
    print('[index-ss] START '+name,flush=True)
    start=time.monotonic()
    with (root/(name+'.log')).open('w') as output:
        child=subprocess.Popen(command,stdout=output,stderr=subprocess.STDOUT)
        while True:
            try:
                status=child.wait(timeout=5);break
            except subprocess.TimeoutExpired:
                print('[index-ss] RUNNING '+name,flush=True)
    results.append(dict(name=name,exit=status,seconds=time.monotonic()-start))
    (root/'summary.json').write_text(json.dumps(results,indent=2)+'\n')
    print(results[-1],flush=True)
raise SystemExit(int(any(row['exit'] for row in results)))
