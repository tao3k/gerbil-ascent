"""Summarize integer fields; complete raw matched samples remain in the receipts."""
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parent
runs = {}
for name in ('first', 'repeat'):
    source = (root / (name + '.sexp')).read_text()
    rows = {}
    for match in re.finditer(r'\(\(name \. ([a-z0-9-]+)\)(.*?)(?=\(\(name \.|\Z)', source, re.S):
        fields = {key: int(value) for key, value in
                  re.findall(r'\(([a-z0-9?-]+) \. ([0-9]+)\)', match[2])}
        fields['primary'] = '(primary? . #t)' in match[2]
        rows[match[1]] = fields
    assert len(rows) == 10
    runs[name] = rows
summary = []
for name in runs['first']:
    rows = [runs[run][name] for run in ('first', 'repeat')]
    allocation_pass = all(row['new-p50-bytes'] < row['old-p50-bytes'] and
                          row['paired-wins'] >= 900 for row in rows)
    timing_pass = all(row['new-p50-ns'] < row['old-p50-ns'] and
                      row['time-paired-wins'] >= 900 for row in rows)
    if rows[0]['primary']:
        assert allocation_pass, name
    summary.append(dict(name=name, primary=rows[0]['primary'],
                        allocation_pass=allocation_pass, timing_pass=timing_pass, runs=rows))
report = dict(runs=['first', 'repeat'], warmups=20, samples=1000, results=summary)
(root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
for row in summary:
    print(row['name'], 'allocation=' + str(row['allocation_pass']),
          'timing=' + str(row['timing_pass']),
          [(r['old-p50-bytes'], r['new-p50-bytes'], r['old-p50-ns'], r['new-p50-ns'],
            r['time-paired-wins']) for r in row['runs']])
