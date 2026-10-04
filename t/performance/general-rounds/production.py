"""Qualify general binary rounds on one compiled Ascent snapshot."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

root = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('performance', 'tools/performance_execution.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
environment = os.environ.copy()

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def full_dependencies():
    library = Path(environment['GERBIL_PATH'])/'lib'
    return {str(p): digest(p) for p in sorted(library.rglob('*'))
            if p.is_file() and 'gerbil-ascent' not in p.relative_to(library).parts
            and (p.suffix in ('.ssi', '.so', '.a', '.o') or re.search(r'\.o\d+$', p.name))}

def run(name, command, exclusive=False):
    began = time.monotonic()
    print('START', name, flush=True)
    with (root/(name+'.log')).open('w') as output:
        child = subprocess.Popen(command, cwd=runner.ROOT, env=environment,
            pass_fds=(int(environment['ASCENT_TEST_EXCLUSIVE_FD']),) if exclusive else (),
            stdout=output, stderr=subprocess.STDOUT)
        while True:
            try:
                status = child.wait(timeout=5)
                break
            except subprocess.TimeoutExpired:
                print('RUNNING', name, flush=True)
    result = dict(name=name, exit=status, seconds=time.monotonic()-began)
    print(result, flush=True)
    return result

if '--production' in sys.argv:
    runner.prepare(environment)
    snapshot = json.loads(Path(environment['ASCENT_PERFORMANCE_SNAPSHOT']).read_text())
    (root/'production-snapshot.json').write_text(json.dumps(snapshot, indent=2)+'\n')
    shutil.copyfile(Path(snapshot['library']).parent/'resolution.log', root/'production-resolution.log')
    dependencies = full_dependencies()
    (root/'native-dependencies.json').write_text(json.dumps(dependencies, indent=2)+'\n')
    results = []
    commands = [('policy', ['timeout', '180s', 'just', 'check-policy'])] + [
        (name, ['just', 'performance-scenario', name]) for name in (
        'ascent-table-expression', 'ascent-table-expression-membership', 'ascent-reachability-closure', 'ascent-binary-program')]
    for name, command in commands:
        runner.verify(snapshot)
        results.append(run(name, command, True))
        runner.verify(snapshot)
        assert full_dependencies() == dependencies
        (root/'gates.json').write_text(json.dumps(results, indent=2)+'\n')
    raise SystemExit(int(any(row['exit'] for row in results)))

if '--recheck' in sys.argv:
    environment['ASCENT_PERFORMANCE_SNAPSHOT'] = str(root/'production-snapshot.json')
    runner.prepare(environment)
    snapshot = json.loads((root/'production-snapshot.json').read_text())
    dependencies = json.loads((root/'native-dependencies.json').read_text())
    assert full_dependencies() == dependencies
    assert not (root/'recheck-gates.json').exists(), 'only one exact-snapshot recheck'
    failed = [r for r in json.loads((root/'gates.json').read_text()) if r['exit']]
    results = []
    for row in failed:
        name = row['name']
        command = ['timeout', '180s', 'just', 'check-policy'] if name == 'policy' else ['just', 'performance-scenario', name]
        runner.verify(snapshot)
        results.append(run('recheck-'+name, command, True))
        runner.verify(snapshot)
        assert full_dependencies() == dependencies
    (root/'recheck-gates.json').write_text(json.dumps(results, indent=2)+'\n')
    raise SystemExit(int(any(row['exit'] for row in results)))

assert not environment.get('ASCENT_TEST_EXCLUSIVE_FD')
package_root = Path(environment['GERBIL_PATH'])/'pkg/github.com/tao3k'
pins = {'asp-gerbil-scheme': 'f5b7c009d2cab61144a8af18008a0bfba3056584',
        'poo-flow-core': 'e85fd45303b208b23e5957fd316e7004994109a4',
        'gerbil-poo': '099b381588360a8a49fd772f666a1a00351366f5'}
for package, commit in pins.items():
    assert subprocess.check_output(['git', '-C', str(package_root/package), 'rev-parse', 'HEAD'], text=True).strip() == commit
    status = subprocess.check_output(['git', '-C', str(package_root/package), 'status', '--porcelain'], text=True)
    # The native package builder writes this untracked manifest, not source edits.
    assert all(line == '?? manifest.ss' for line in status.splitlines()), status
(root/'dependency-pins.json').write_text(json.dumps(dict(asp_tag='v0.1.2.2',
    asp_tag_object='0b59cb7d6d29d545ae735741057452bdb5e77aea', commits=pins), indent=2)+'\n')
if '--resume' in sys.argv:
    assert (root/'production-snapshot.json').exists()
    if not (root/'recheck-gates.json').exists():
        run('recheck-production', ['python3', 'tools/test_execution.py', 'run', '--',
            'python3', str(Path(__file__).resolve()), '--recheck'])
else:
    assert run('production', ['python3', 'tools/test_execution.py', 'run', '--',
        'python3', str(Path(__file__).resolve()), '--production'])['exit'] == 0
snapshot = json.loads((root/'production-snapshot.json').read_text())
dependencies = json.loads((root/'native-dependencies.json').read_text())
runner.verify(snapshot)
environment['ASCENT_TEST_LIBRARY'] = snapshot['library']
environment['GERBIL_LOADPATH'] = snapshot['library']+':'+str(runner.ROOT)+(':'+environment['GERBIL_LOADPATH'] if environment.get('GERBIL_LOADPATH') else '')
result = run('functional-suite', ['timeout', '600s', 'just', 'test'])
assert result['exit'] == 0
runner.verify(snapshot)
assert full_dependencies() == dependencies
match = re.search(r'\[test-suite\] END modules=(\d+) failed=0 receipt=(\S+)', (root/'functional-suite.log').read_text())
assert match
receipt = json.loads(Path(match[2]).read_text())
assert not receipt['failed'] and sorted(receipt['requested']) == sorted(r['module'] for r in receipt['results'])
logs = root/'modules'
logs.mkdir(exist_ok=True)
coverage = []
for row in receipt['results']:
    assert row['exit'] == 0
    text = Path(row['log']).read_text()
    cases = re.findall(r'^CASE-OK (.+)$', text, re.M)
    assert cases and len(cases) == len(re.findall(r'^CASE (.+)$', text, re.M))
    assert 'MODULE-OK '+row['module'] in text and 'HARNESS-OK' in text and re.search(r'^OK$', text, re.M)
    assert not re.search(r'ERROR (CASE|MODULE|HARNESS|CHECK)|Heap overflow|Stack overflow', text)
    shutil.copyfile(row['log'], logs/Path(row['log']).name)
    coverage.append(dict(module=row['module'], cases=cases, count=len(cases)))
(root/'suite-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
(root/'suite-coverage.json').write_text(json.dumps(dict(modules=len(coverage),
    cases=sum(r['count'] for r in coverage), coverage=coverage), indent=2)+'\n')
gates = {r['name']: r['exit'] for r in json.loads((root/'gates.json').read_text())}
if (root/'recheck-gates.json').exists():
    gates.update({r['name'].removeprefix('recheck-'): r['exit'] for r in json.loads((root/'recheck-gates.json').read_text())})
(root/'verification.json').write_text(json.dumps(dict(sources=snapshot['sources'],
    qualifier_sha256=digest(Path(__file__)), native_artifacts_verified=True,
    dependencies_verified=len(dependencies), suite=result, modules=len(coverage),
    cases=sum(r['count'] for r in coverage), pins=pins,
    original_gates_after_recheck=gates, original_gates_passed=not any(gates.values())), indent=2)+'\n')
print('VERIFIED', len(coverage), 'modules', sum(r['count'] for r in coverage), 'Cases', flush=True)
