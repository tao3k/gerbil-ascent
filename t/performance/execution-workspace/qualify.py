"""Run the final immutable workspace source through native qualification gates."""
import json
import subprocess
import time
from pathlib import Path

root = Path('t/performance/execution-workspace')
commands = [
    ('policy-final', ['just', 'check-policy']),
    ('full-suite-final', ['just', 'test']),
    ('nonpositive-ss', ['just', 'performance-scenario', 'ascent-nonpositive-session-update']),
    ('table-expression-ss', ['just', 'performance-scenario', 'ascent-table-expression']),
]
results = []
for name, command in commands:
    print('[workspace-qualification] START '+name, flush=True)
    started = time.monotonic()
    with (root/(name+'.log')).open('w') as output:
        child = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
        while True:
            try:
                status = child.wait(timeout=5)
                break
            except subprocess.TimeoutExpired:
                print('[workspace-qualification] RUNNING '+name, flush=True)
    results.append(dict(name=name, exit=status, seconds=time.monotonic()-started))
    (root/'qualification-summary.json').write_text(json.dumps(results, indent=2)+'\n')
    print(results[-1], flush=True)
    if status and name in ('policy-final', 'full-suite-final'):
        raise SystemExit(status)
raise SystemExit(int(any(row['exit'] for row in results)))
