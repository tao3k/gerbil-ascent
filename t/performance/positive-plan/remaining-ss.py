"""Continue the unchanged SS inventory after the first four recorded entries."""
import json
import os
from pathlib import Path
import subprocess
import time

root = Path.cwd()
receipts = root / 't/performance/positive-plan/remaining-ss'
receipts.mkdir(exist_ok=True)
scenarios = ['ascent-rule-clauses', 'ascent-var-points-to', 'ascent-upstream-examples',
             'ascent-product-session', 'ascent-mutual-recursive-heads',
             'ascent-derived-aggregate', 'ascent-indexed-joins', 'ascent-byods-eqrel']
commands = [(name, ['just', 'performance-scenario', name]) for name in scenarios]
commands += [('ascent-binary-program', ['just', 'test-file', 't/performance/ascent-binary-program-performance-test.ss'])]
commands += [(name, ['just', 'performance-scenario', name]) for name in
             ['ascent-reachability-closure', 'ascent-table-expression', 'ascent-table-expression-membership']]
commands += [('ascent-shortest-candidates', ['just', 'test-file', 't/performance/ascent-shortest-candidates-performance-test.ss'])]
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
    if status:
        raise SystemExit(status)
