"""Qualify a fixed demand-driven publication path with complete-result timing."""
import json
import os
from pathlib import Path
import subprocess
import time
root=Path(__file__).resolve().parent
commands=[('final-first',['just','result-benchmark']),
          ('final-repeat',['just','result-benchmark']),
          ('final-policy',['just','check-policy']),
          ('final-suite',['just','test'])]
commands += [(name,['just','performance-scenario',name]) for name in
             ('ascent-session-update','ascent-ten-thousand-appends',
              'ascent-nonpositive-session-update','ascent-product-session')]
results=[]
for name,command in commands:
    print('[result-publication] START '+name,flush=True)
    start=time.monotonic()
    environment=os.environ.copy()
    environment['ASCENT_RESULT_RECEIPT']=str(root/(name+'.sexp'))
    with (root/(name+'.log')).open('w') as output:
        child=subprocess.Popen(command,stdout=output,stderr=subprocess.STDOUT,env=environment)
        while True:
            try:
                status=child.wait(timeout=5);break
            except subprocess.TimeoutExpired:
                print('[result-publication] RUNNING '+name,flush=True)
    results.append(dict(name=name,exit=status,seconds=time.monotonic()-start))
    (root/'summary.json').write_text(json.dumps(results,indent=2)+'\n')
    print(results[-1],flush=True)
    if status and name.startswith('final-'):
        raise SystemExit(status)
raise SystemExit(int(any(r['exit'] for r in results)))
