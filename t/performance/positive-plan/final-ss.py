"""Finish the two unchanged SS entries after the recorded table-expression failure."""
import json
import os
from pathlib import Path
import subprocess
import time

root = Path.cwd()
receipts = root / 't/performance/positive-plan/final-ss'
receipts.mkdir(exist_ok=True)
commands = [('ascent-table-expression-membership', ['just', 'performance-scenario', 'ascent-table-expression-membership']), ('ascent-shortest-candidates', ['just', 'test-file', 't/performance/ascent-shortest-candidates-performance-test.ss'])]
lease = int(os.environ['ASCENT_TEST_EXCLUSIVE_FD'])
results = []
for name, command in commands:
    started = time.monotonic()
    print('[remaining-ss] START '+name, flush=True)
    with (receipts / (name+'.log')).open('w') as output:
        child = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                                 pass_fds=(lease,))
        while True:
            try:
                status = child.wait(timeout=5)
                break
            except subprocess.TimeoutExpired:
                print('[remaining-ss] RUNNING '+name, flush=True)
    result = dict(name=name, exit=status, seconds=time.monotonic()-started)
    results.append(result)
    (receipts/'summary.json').write_text(json.dumps(dict(requested=[n for n, _ in commands], results=results),indent=2)+'\n')
    print(result,flush=True)
raise SystemExit(int(any(row['exit'] for row in results)))
