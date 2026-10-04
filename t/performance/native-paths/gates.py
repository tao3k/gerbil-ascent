"""Qualify the three original relation gates on one compiled production snapshot."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

root = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('performance', 'tools/performance_execution.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
environment = os.environ.copy()
runner.prepare(environment)
snapshot = json.loads(Path(environment['ASCENT_PERFORMANCE_SNAPSHOT']).read_text())
(root / 'production-snapshot.json').write_text(json.dumps(snapshot, indent=2) + '\n')
(root / 'production-resolution.log').write_text(
    (Path(snapshot['library']).parent / 'resolution.log').read_text())
results = []
commands = [('policy', ['just', 'check-policy'])] + [
    (name, ['just', 'performance-scenario', name]) for name in (
        'ascent-table-expression', 'ascent-table-expression-membership', 'ascent-reachability-closure')]
for name, command in commands:
    runner.verify(snapshot)
    print('[native-paths] START ' + name, flush=True)
    started = time.monotonic()
    with (root / (name + '.log')).open('w') as output:
        child = subprocess.Popen(command, cwd=runner.ROOT, env=environment,
                                 pass_fds=(int(environment['ASCENT_TEST_EXCLUSIVE_FD']),),
                                 stdout=output, stderr=subprocess.STDOUT)
        while True:
            try:
                status = child.wait(timeout=5)
                break
            except subprocess.TimeoutExpired:
                print('[native-paths] RUNNING ' + name, flush=True)
    runner.verify(snapshot)
    results.append(dict(name=name, exit=status, seconds=time.monotonic() - started))
    (root / 'gates.json').write_text(json.dumps(results, indent=2) + '\n')
    print(results[-1], flush=True)
raise SystemExit(int(any(row['exit'] for row in results)))
