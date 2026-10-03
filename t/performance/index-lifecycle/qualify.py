"""Run fixed-source qualification with isolated, sequential timing stages."""
import json
import os
from pathlib import Path
import subprocess
import time
root = Path(__file__).resolve().parent
commands = [('first', ['just', 'index-lifecycle-benchmark']),
            ('repeat', ['just', 'index-lifecycle-benchmark']),
            ('suite', ['just', 'test']),
            ('original-ss', ['just', 'performance'])]
results = []
for name, command in commands:
    print('[index-lifecycle] START '+name, flush=True)
    start = time.monotonic()
    environment = os.environ.copy()
    environment['ASCENT_INDEX_LIFECYCLE_RECEIPT'] = str(root/(name+'.sexp'))
    with (root/(name+'.log')).open('w') as output:
        child = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, env=environment)
        while True:
            try:
                status = child.wait(timeout=5)
                break
            except subprocess.TimeoutExpired:
                print('[index-lifecycle] RUNNING '+name, flush=True)
    results.append(dict(name=name, exit=status, seconds=time.monotonic()-start))
    (root/'summary.json').write_text(json.dumps(results, indent=2)+'\n')
    print(results[-1], flush=True)
    if status:
        raise SystemExit(status)
