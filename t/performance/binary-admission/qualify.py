"""Two native complete-output comparisons against the exact preceding module."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

root = Path(__file__).resolve().parent
repository = root.parents[2]
baseline = (root / 'baseline.txt').read_text().strip()
original = subprocess.check_output(['git', 'show', baseline+':table/expression.ss'], cwd=repository, text=True)
expected = original.replace('gerbil-ascent-table-expression-prototype', 'binary-admission-reference-expression-prototype').replace('gerbil-ascent-relation-closure-bounded', 'binary-admission-reference-closure-bounded')
assert expected == (root/'reference-expression.ss').read_text(), 'reference expression drift'
program = subprocess.check_output(['git', 'show', baseline+':core/binary-program.ss'], cwd=repository, text=True)
reference = program.replace(':gerbil-ascent/table/expression', ':gerbil-ascent/t/performance/binary-admission/reference-expression').replace('gerbil-ascent-relation-closure-bounded', 'binary-admission-reference-closure-bounded').replace('gerbil-ascent-binary-', 'binary-admission-reference-binary-').replace('gerbil-ascent-evaluate-binary-program', 'binary-admission-reference-evaluate-binary-program')
assert reference == (root/'reference-program.ss').read_text(), 'reference program drift'
environment = os.environ.copy()
library = repository / '.gerbil/binary-admission/lib'
environment['ASCENT_BINARY_ADMISSION_LIB'] = str(library)
environment['ASCENT_BINARY_ADMISSION_BUILD_DEPS'] = str(library.parent / 'build-deps')
environment['GERBIL_LOADPATH'] = str(library) + (
    ':' + environment['GERBIL_LOADPATH'] if environment.get('GERBIL_LOADPATH') else '')
descriptor = int(environment['ASCENT_TEST_EXCLUSIVE_FD'])
paths = ['table/expression.ss', 'core/binary-program.ss', 't/qualification/ascent-binary-program-test.ss',
         'justfile', *[str(p.relative_to(repository)) for p in sorted(root.glob('*.ss'))],
         str(Path(__file__).resolve().relative_to(repository))]

def manifest():
    return {name: hashlib.sha256((repository / name).read_bytes()).hexdigest() for name in paths}

import re

def dependencies():
    lib = Path(environment['GERBIL_PATH'])/'lib'
    return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(lib.rglob('*'))
            if p.is_file() and 'gerbil-ascent' not in p.relative_to(lib).parts
            and (p.suffix in ('.ssi', '.so', '.a', '.o') or re.search(r'\.o\d+$', p.name))}
sources = manifest()
native_dependencies = dependencies()
(root/'native-dependencies.json').write_text(json.dumps(native_dependencies, indent=2)+'\n')
(root / 'reference-verification.json').write_text(json.dumps(dict(
    commit=baseline, verified=True,
    source_sha256=hashlib.sha256(original.encode()).hexdigest(), program_sha256=hashlib.sha256(program.encode()).hexdigest(), reference_program_sha256=hashlib.sha256(reference.encode()).hexdigest(),
    reference_sha256=hashlib.sha256(expected.encode()).hexdigest(),
    adaptations=['exported identifiers alpha renamed; reference table import redirected']), indent=2) + '\n')
results = []

def run(name, arguments, cases=None):
    print('[binary-admission] START ' + name, flush=True)
    started = time.monotonic()
    with (root / (name + '.log')).open('w') as output:
        child = subprocess.Popen(arguments, cwd=repository, env=environment,
                                 pass_fds=(descriptor,), stdout=output, stderr=subprocess.STDOUT)
        observed_size = 0
        last_progress = time.monotonic()
        while True:
            try:
                status = child.wait(timeout=5)
                break
            except subprocess.TimeoutExpired:
                size = (root / (name + '.log')).stat().st_size
                if size != observed_size:
                    observed_size = size
                    last_progress = time.monotonic()
                if name != 'build' and time.monotonic() - last_progress > 10:
                    child.kill()
                    child.wait()
                    raise RuntimeError('native probe stopped making progress: ' + name)
                print('[binary-admission] RUNNING ' + name, flush=True)
    log = (root / (name + '.log')).read_text()
    assert not status, log[-3000:]
    assert not any(marker in log for marker in ('ERROR', 'Heap overflow', 'Stack overflow')), log[-3000:]
    if cases:
        assert sum(line.startswith('RESULT ') for line in log.splitlines()) == cases
        assert sum(line.startswith('NATIVE-MODULE-OK ') for line in log.splitlines()) == 4
        assert 'OK' in log.splitlines()
    assert manifest() == sources, 'sources changed during qualification'
    assert dependencies() == native_dependencies, 'native dependency drift'
    results.append(dict(name=name, exit=status, seconds=time.monotonic() - started))
    (root / 'summary.json').write_text(json.dumps(results, indent=2) + '\n')
    print(results[-1], flush=True)

run('build', ['timeout', '150s', 'gxi', '-:max-heap=1G,debug=q', str(root / 'build.ss')])
artifacts = {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in library.rglob('*') if p.is_file()}
run('oracle', ['timeout', '180s', 'gxi', '-:max-heap=1G,debug=q', str(root / 'oracle.ss')])
assert 'OK' in (root / 'oracle.log').read_text().splitlines()
for name in ('first', 'repeat'):
    environment['ASCENT_BINARY_ADMISSION_RECEIPT'] = str(root / (name + '.sexp'))
    run(name, ['timeout', '480s', 'gxi', '-:max-heap=1G,debug=q', str(root / 'benchmark.ss')], 12)
    assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest() == h for p, h in artifacts.items())
(root / 'qualified.json').write_text(json.dumps(dict(sources=sources, artifacts=artifacts), indent=2) + '\n')
