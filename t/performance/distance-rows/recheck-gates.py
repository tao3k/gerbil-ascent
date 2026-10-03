"""Recheck failed original gates without changing sources, fixtures or budgets."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
root = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('performance', 'tools/performance_execution.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
snapshot = json.loads((root/'production-snapshot.json').read_text())
environment = os.environ.copy()
environment['ASCENT_PERFORMANCE_SNAPSHOT'] = str(root/'production-snapshot.json')
runner.prepare(environment)
original = json.loads((root/'gates.json').read_text())
shutil.copyfile(root/'gates.json', root/'initial-gates.json')
results = []
for row in original:
    if not row['exit']:
        continue
    name = row['name']
    shutil.copyfile(root/(name+'.log'), root/('failed-'+name+'.log'))
    command = ['just', 'check-policy'] if name == 'policy' else ['just', 'performance-scenario', name]
    print('[distance-rows] RECHECK ' + name, flush=True)
    runner.verify(snapshot)
    began = time.monotonic()
    with (root/('recheck-'+name+'.log')).open('w') as output:
        child = subprocess.Popen(command, cwd=runner.ROOT, env=environment, pass_fds=(int(environment['ASCENT_TEST_EXCLUSIVE_FD']),), stdout=output, stderr=subprocess.STDOUT)
        while True:
            try:
                status = child.wait(timeout=5)
                break
            except subprocess.TimeoutExpired:
                print('[distance-rows] RECHECK RUNNING ' + name, flush=True)
    runner.verify(snapshot)
    results.append(dict(name=name, exit=status, seconds=time.monotonic()-began))
(root/'recheck-gates.json').write_text(json.dumps(results, indent=2)+'\n')
print(results, flush=True)
raise SystemExit(int(any(r['exit'] for r in results)))
