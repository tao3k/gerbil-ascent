"""Qualify a fixed relation implementation with native gates and paired runs."""
import json
import os
from pathlib import Path
import subprocess
import time

root = Path('t/performance/relation-materialization')
commands = [
    ('policy-complete', ['just', 'check-policy']),
    ('full-suite', ['just', 'test']),
    ('paired-first', ['just', 'materialization-benchmark']),
    ('paired-repeat', ['just', 'materialization-benchmark']),
    ('original-table-expression', ['just', 'performance-scenario', 'ascent-table-expression']),
    ('original-membership', ['just', 'performance-scenario', 'ascent-table-expression-membership']),
    ('original-closure', ['just', 'performance-scenario', 'ascent-reachability-closure']),
]
results = []
for name, command in commands:
    print('[materialization] START '+name, flush=True)
    began = time.monotonic()
    environment = os.environ.copy()
    environment['ASCENT_MATERIALIZATION_RECEIPT'] = str((root/(name+'.sexp')).resolve())
    with (root/(name+'.log')).open('w') as output:
        child = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, env=environment)
        while True:
            try:
                status = child.wait(timeout=5)
                break
            except subprocess.TimeoutExpired:
                print('[materialization] RUNNING '+name, flush=True)
    results.append(dict(name=name, exit=status, seconds=time.monotonic()-began))
    (root/'qualification-summary.json').write_text(json.dumps(results, indent=2)+'\n')
    print(results[-1], flush=True)
    if status and name in ('policy-complete', 'full-suite', 'paired-first', 'paired-repeat'):
        raise SystemExit(status)
raise SystemExit(int(any(row['exit'] for row in results)))
