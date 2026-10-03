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
        arrays = {key: [int(value) for value in values.split()] for key, values in
                  re.findall(r'\((old-samples-bytes|new-samples-bytes|old-samples-ns|new-samples-ns) ([-0-9 ]+)\)', match[2], re.S)}
        assert len(arrays) == 4 and all(len(values) == 1000 for values in arrays.values())
        for unit, field in [('bytes', 'paired-wins'), ('ns', 'time-paired-wins')]:
            assert fields[field] == sum(new < old for old, new in
                zip(arrays['old-samples-' + unit], arrays['new-samples-' + unit]))
        fields['negative-counter-deltas'] = sum(value < 0 for key, values in arrays.items() if key.endswith('bytes') for value in values)
        fields['primary'] = '(primary? . #t)' in match[2]
        rows[match[1]] = fields
    assert len(rows) == 24
    runs[name] = rows
summary = []
for name in runs['first']:
    rows = [runs[run][name] for run in ('first', 'repeat')]
    counter_delta_decrease = all(row['new-p50-bytes'] < row['old-p50-bytes'] and
                          row['paired-wins'] >= 900 for row in rows)
    timing_pass = all(row['new-p50-ns'] < row['old-p50-ns'] and
                      row['time-paired-wins'] >= 900 for row in rows)
    summary.append(dict(name=name, primary=rows[0]['primary'],
                        counter_delta_decrease=counter_delta_decrease, allocation_qualified=False, timing_pass=timing_pass, runs=rows))
report = dict(runs=['first', 'repeat'], warmups=20, samples=1000,
              allocation_qualified=False,
              allocation_limitation='Negative process-statistics counter deltas observed; allocation claims withheld for the study.',
              negative_counter_deltas={run: sum(row['negative-counter-deltas'] for row in results.values()) for run, results in runs.items()},
              previous_measurement_audit={'ordered-relations': dict(first_negative=86, repeat_negative=86, observations_per_run=20000, allocation_qualification='withdrawn')},
              results=summary)
(root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
for row in summary:
    print(row['name'], 'counter_delta_decrease=' + str(row['counter_delta_decrease']),
          'timing=' + str(row['timing_pass']),
          [(r['old-p50-bytes'], r['new-p50-bytes'], r['old-p50-ns'], r['new-p50-ns'],
            r['time-paired-wins']) for r in row['runs']])
