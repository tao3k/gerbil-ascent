"""Timing-only qualification: allocation counter evidence remains withdrawn."""
import json
from pathlib import Path
import re
root = Path(__file__).resolve().parent
runs = {}
for run in ('first', 'repeat'):
    rows = {}
    source = (root / (run + '.sexp')).read_text()
    for match in re.finditer(r'\(\(name \. ([a-z0-9-]+)\)(.*?)(?=\(\(name \.|\Z)', source, re.S):
        fields = {key: int(value) for key, value in re.findall(r'\(([a-z0-9?-]+) \. ([0-9]+)\)', match[2])}
        arrays = {key: [int(value) for value in values.split()] for key, values in
                  re.findall(r'\((old-samples-ns|new-samples-ns) ([0-9 ]+)\)', match[2])}
        assert len(arrays) == 2 and all(len(a) == 1000 for a in arrays.values())
        assert fields['time-paired-wins'] == sum(new < old for old, new in zip(arrays['old-samples-ns'], arrays['new-samples-ns']))
        fields['primary'] = '(primary? . #t)' in match[2]
        rows[match[1]] = fields
    assert len(rows) == 19
    runs[run] = rows
results = []
for name in runs['first']:
    samples = [runs[run][name] for run in ('first', 'repeat')]
    qualified = all(r['new-p50-ns'] < r['old-p50-ns'] and r['time-paired-wins'] >= 900 for r in samples)
    results.append(dict(name=name, primary=samples[0]['primary'], timing_qualified=qualified, runs=samples))
report = dict(warmups=20, samples=1000, allocation_qualified=False, results=results)
(root/'report.json').write_text(json.dumps(report, indent=2)+'\n')
for r in results:
    print(r['name'], r['timing_qualified'], [(s['old-p50-ns'], s['new-p50-ns'], s['time-paired-wins']) for s in r['runs']])
assert all(r['timing_qualified'] for r in results if r['name'] in ('complete-degree-31-32', 'closure-fanout-32', 'distance-then-closure-32')), 'shared native path demands must qualify'
