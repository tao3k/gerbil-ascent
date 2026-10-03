"""Bind final semantic coverage and timing classifications to native artifacts."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re

root = Path(__file__).resolve().parent
def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

paired = json.loads((root/'qualified.json').read_text())
assert all(digest(p) == h for p, h in paired['sources'].items())
assert all(digest(p) == h for p, h in paired['artifacts'].items())
snapshot = json.loads((root/'production-snapshot.json').read_text())
os.environ['GERBIL_PATH'] = snapshot['gerbil_path']
spec = importlib.util.spec_from_file_location('performance', 'tools/performance_execution.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
assert len(runner.verify(snapshot)) == 41
coverage = json.loads((root/'suite-coverage.json').read_text())
assert (coverage['modules'], coverage['cases']) == (48, 373)
receipt = json.loads((root/'suite-receipt.json').read_text())
assert not receipt['failed']
assert sorted(receipt['requested']) == sorted(r['module'] for r in receipt['results'])
for row in coverage['coverage']:
    text = (root/'qualification'/(Path(row['module']).stem+'.log')).read_text()
    assert re.findall(r'^CASE-OK (.+)$', text, re.M) == row['cases']
    assert len(re.findall(r'^CASE (.+)$', text, re.M)) == row['count']
    assert 'MODULE-OK '+row['module'] in text and 'HARNESS-OK' in text and re.search(r'^OK$', text, re.M)
    assert not re.search(r'ERROR (CASE|MODULE|HARNESS|CHECK)|Heap overflow|Stack overflow', text)
gates = json.loads((root/'gates.json').read_text())
assert len(gates) == 4 and all(g['exit'] == 0 for g in gates)
for gate in gates:
    if gate['name'] == 'policy':
        continue
    text = (root/(gate['name']+'.log')).read_text()
    assert 'CASE-OK bounded scenario' in text and 'MODULE-OK' in text and 'HARNESS-OK' in text and re.search(r'^OK$', text, re.M)
    assert not re.search(r'ERROR (CASE|MODULE|HARNESS|CHECK)|Heap overflow|Stack overflow', text)
for run in ('first', 'repeat'):
    matches = list(re.finditer(r'\(\(name \. ([a-z0-9-]+)\)(.*?)(?=\(\(name \.|\Z)', (root/(run+'.sexp')).read_text(), re.S))
    assert len(matches) == 19
    for match in matches:
        fields = {k: int(v) for k, v in re.findall(r'\(([a-z0-9?-]+) \. ([0-9]+)\)', match[2])}
        arrays = {k: list(map(int, v.split())) for k, v in re.findall(r'\((old-samples-ns|new-samples-ns) ([0-9 ]+)\)', match[2])}
        assert len(arrays) == 2 and all(len(a) == 1000 for a in arrays.values())
        for side in ('old', 'new'):
            ordered = sorted(arrays[side+'-samples-ns'])
            assert fields[side+'-p50-ns'] == ordered[499] and fields[side+'-p95-ns'] == ordered[949]
        assert fields['time-paired-wins'] == sum(n < o for o, n in zip(arrays['old-samples-ns'], arrays['new-samples-ns']))
for name in ('explore-manifest.json', 'explore-early-manifest.json'):
    exploration = json.loads((root/name).read_text())
    assert all(digest(p) == h for p, h in exploration['sources'].items())
    for path, expected in exploration['artifacts'].items():
        assert digest(exploration.get('artifact_archive', {}).get(path, path)) == expected
sources = {**snapshot['sources'], **paired['sources']}
for path in root.glob('*.py'):
    sources[str(path.relative_to(runner.ROOT))] = digest(path)
sources[str((root/'README.md').relative_to(runner.ROOT))] = digest(root/'README.md')
report = json.loads((root/'report.json').read_text())
qualified = [r['name'] for r in report['results'] if r['timing_qualified']]
assert qualified == ['distance-then-closure-32']
(root/'final-verification.json').write_text(json.dumps(dict(
    sources=sources, paired_artifacts_verified=True, production_artifacts_verified=True,
    paired_raw_percentiles_and_wins_verified=True, exploratory_sources_and_archived_artifacts_verified=True,
    gerbil_path=snapshot['gerbil_path'], dependencies_verified=len(snapshot['dependencies']),
    production_modules=41, modules=48, cases=373,
    functional_coverage=receipt.get('completion', 'uninterrupted suite'),
    initial_suite_collection_exit=receipt.get('initial_collection_exit'),
    original_production_gates_passed=True, experimental_timing_assertion_passed=False,
    timing_qualified_profiles=qualified, allocation_qualified=False), indent=2)+'\n')
print('VERIFIED native artifacts, 41 production modules, 48 functional modules, 373 Cases; experimental timing assertion remains failed')
