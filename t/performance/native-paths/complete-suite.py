"""Complete only modules interrupted by the aggregate collection deadline."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

root = Path(__file__).resolve().parent

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

runner = module('performance', 'tools/performance_execution.py')
scheduler = module('scheduler', 'tools/test_execution.py')
snapshot = json.loads((root/'production-snapshot.json').read_text())
runner.verify(snapshot)
assert not os.environ.get('ASCENT_TEST_EXCLUSIVE_FD')
assert 'suite exit 124 ' in (root/'suite-collection.log').read_text()
text = (root/'final-functional-suite.log').read_text()
initial = []
requested = []
for lane in ('parallel', 'exclusive'):
    paths = re.findall(r'\['+lane+r'-test\].*?logs=(\S+)', text)
    assert paths and len(set(paths)) == 1
    directory = Path(paths[0])
    receipt = json.loads((directory/'summary.json').read_text())
    shutil.copyfile(directory/'summary.json', root/('interrupted-'+lane+'-summary.json'))
    saved = root/'interrupted-qualification'
    saved.mkdir(exist_ok=True)
    for log in directory.glob('*.log'):
        shutil.copyfile(log, saved/log.name)
    requested.extend(receipt['requested'])
    initial.extend(r for r in receipt['results'] if r['exit'] == 0)
expected = sorted(str(p.relative_to(runner.ROOT)) for p in (runner.ROOT/'t/qualification').glob('*-test.ss'))
assert sorted(requested) == expected and len(set(requested)) == len(requested)
completed = {r['module'] for r in initial}
remaining = [p for p in expected if p not in completed]
assert remaining, 'no incomplete modules to qualify'
print('COMPLETING', remaining, flush=True)
os.environ['ASCENT_TEST_LIBRARY'] = snapshot['library']
os.environ['GERBIL_LOADPATH'] = snapshot['library'] + ':' + str(runner.ROOT) + (':' + os.environ['GERBIL_LOADPATH'] if os.environ.get('GERBIL_LOADPATH') else '')
results = scheduler.execute_modules(remaining, 1, 'exclusive')
runner.verify(snapshot)
assert len(results) == len(remaining) and all(r['exit'] == 0 for r in results)
combined = sorted(initial + results, key=lambda r: r['module'])
assert sorted(r['module'] for r in combined) == expected
receipt = root/'completed-suite.json'
receipt.write_text(json.dumps(dict(requested=expected, results=combined, failed=False,
    completion='interrupted suite plus exact-snapshot missing modules',
    initial_collection_exit=124, initial_collection_limit_seconds=360,
    completed_after_interruption=remaining), indent=2)+'\n')
print('[test-suite] END modules='+str(len(expected))+' failed=0 receipt='+str(receipt), flush=True)
subprocess.run(['python3', str(root/'collect-suite.py')], check=True)
