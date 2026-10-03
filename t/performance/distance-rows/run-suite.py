"""Run the native functional suite after the exclusive collectors have exited."""
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
snapshot = json.loads((root/'production-snapshot.json').read_text())
runner.verify(snapshot)
environment = os.environ.copy()
assert not environment.get('ASCENT_TEST_EXCLUSIVE_FD'), 'run the suite outside the collector lease'
environment['ASCENT_TEST_LIBRARY'] = snapshot['library']
environment['GERBIL_LOADPATH'] = snapshot['library'] + ':' + str(runner.ROOT) + (':' + environment['GERBIL_LOADPATH'] if environment.get('GERBIL_LOADPATH') else '')
started = time.monotonic()
with (root/'final-functional-suite.log').open('w') as output:
    child = subprocess.Popen(['timeout', '360s', 'just', 'test'], env=environment, cwd=runner.ROOT, stdout=output, stderr=subprocess.STDOUT)
    while True:
        try:
            status = child.wait(timeout=5)
            break
        except subprocess.TimeoutExpired:
            print('[distance-rows] SUITE RUNNING', flush=True)
runner.verify(snapshot)
print('suite exit', status, 'seconds', time.monotonic()-started, flush=True)
assert status == 0, 'functional suite failed; preserved raw log'
subprocess.run(['python3', str(root/'collect-suite.py')], cwd=runner.ROOT, check=True)
