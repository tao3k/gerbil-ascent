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
original = subprocess.check_output(
    ['git', 'show', baseline + ':table/expression.ss'], cwd=repository, text=True)
expected = original.replace('gerbil-ascent-table-expression-prototype',
                            'ordered-relations-reference-prototype').replace(
    'gerbil-ascent-relation-closure-bounded', 'ordered-relations-reference-closure-bounded')
assert expected == (root / 'reference.ss').read_text(), 'reference drift'
environment = os.environ.copy()
library = repository / '.gerbil/ordered-relations/lib'
environment['ASCENT_ORDERED_RELATIONS_LIB'] = str(library)
environment['ASCENT_ORDERED_RELATIONS_BUILD_DEPS'] = str(library.parent / 'build-deps')
environment['GERBIL_LOADPATH'] = str(library) + (
    ':' + environment['GERBIL_LOADPATH'] if environment.get('GERBIL_LOADPATH') else '')
descriptor = int(environment['ASCENT_TEST_EXCLUSIVE_FD'])
paths = ['table/expression.ss', 't/qualification/ascent-materialization-test.ss',
         'justfile', *[str(p.relative_to(repository)) for p in sorted(root.glob('*.ss'))],
         str(Path(__file__).resolve().relative_to(repository))]

def manifest():
    return {name: hashlib.sha256((repository / name).read_bytes()).hexdigest() for name in paths}

sources = manifest()
(root / 'reference-verification.json').write_text(json.dumps(dict(
    commit=baseline, verified=True,
    source_sha256=hashlib.sha256(original.encode()).hexdigest(),
    reference_sha256=hashlib.sha256(expected.encode()).hexdigest(),
    adaptations=['two exported names alpha renamed']), indent=2) + '\n')
results = []

def run(name, arguments, cases=None):
    print('[ordered-relations] START ' + name, flush=True)
    started = time.monotonic()
    with (root / (name + '.log')).open('w') as output:
        child = subprocess.Popen(arguments, cwd=repository, env=environment,
                                 pass_fds=(descriptor,), stdout=output, stderr=subprocess.STDOUT)
        while True:
            try:
                status = child.wait(timeout=5)
                break
            except subprocess.TimeoutExpired:
                print('[ordered-relations] RUNNING ' + name, flush=True)
    log = (root / (name + '.log')).read_text()
    assert not status, log[-3000:]
    assert not any(marker in log for marker in ('ERROR', 'Heap overflow', 'Stack overflow')), log[-3000:]
    if cases:
        assert sum(line.startswith('RESULT ') for line in log.splitlines()) == cases
        assert sum(line.startswith('NATIVE-MODULE-OK ') for line in log.splitlines()) == 2
        assert 'OK' in log.splitlines()
    assert manifest() == sources, 'sources changed during qualification'
    results.append(dict(name=name, exit=status, seconds=time.monotonic() - started))
    (root / 'summary.json').write_text(json.dumps(results, indent=2) + '\n')
    print(results[-1], flush=True)

run('build', ['timeout', '150s', 'gxi', '-:max-heap=1G,debug=q', str(root / 'build.ss')])
artifacts = {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in library.rglob('*') if p.is_file()}
for name in ('first', 'repeat'):
    environment['ASCENT_ORDERED_RELATIONS_RECEIPT'] = str(root / (name + '.sexp'))
    run(name, ['timeout', '180s', 'gxi', '-:max-heap=1G,debug=q', str(root / 'benchmark.ss')], 10)
    assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest() == h for p, h in artifacts.items())
(root / 'qualified.json').write_text(json.dumps(dict(sources=sources, artifacts=artifacts), indent=2) + '\n')
