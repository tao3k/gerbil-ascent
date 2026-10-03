"""Recompute timing statistics from all raw native paired samples."""
import json
from pathlib import Path
import re
root=Path(__file__).resolve().parent
runs={}
for run in ('first','repeat'):
    rows={}
    source=(root/(run+'.sexp')).read_text()
    for match in re.finditer(r'\(\(name \. ([a-z0-9-]+)\)(.*?)(?=\(\(name \.|\Z)',source,re.S):
        fields={k:int(v) for k,v in re.findall(r'\(([a-z0-9?-]+) \. ([0-9]+)\)',match[2])}
        arrays={k:list(map(int,v.split())) for k,v in re.findall(r'\((old-samples-ns|new-samples-ns) ([-0-9 ]+)\)',match[2],re.S)}
        assert len(arrays)==2 and all(len(v)==1000 for v in arrays.values())
        for kind in ('old','new'):
            samples=sorted(arrays[kind+'-samples-ns'])
            assert samples[499]==fields[kind+'-p50-ns'] and samples[949]==fields[kind+'-p95-ns']
        assert fields['time-paired-wins']==sum(n<o for o,n in zip(arrays['old-samples-ns'],arrays['new-samples-ns']))
        rows[match[1]]=fields
    assert len(rows)==14
    runs[run]=rows
results=[]
controls={'general-copy-32','general-join-32','general-guard-32','specialized-chain-20','specialized-degree-31-32'}
for name in runs['first']:
    rows=[runs[r][name] for r in ('first','repeat')]
    results.append(dict(name=name,control=name in controls,
        timing_qualified=all(r['new-p50-ns']<r['old-p50-ns'] and r['time-paired-wins']>=900 for r in rows),
        control_within_ten_percent=all(r['new-p50-ns']<=r['old-p50-ns']*1.1 for r in rows) if name in controls else None,
        runs=rows))
report=dict(warmups=20,samples=1000,runs=['first','repeat'],allocation_claim=False,results=results)
(root/'report.json').write_text(json.dumps(report,indent=2)+'\n')
for r in results:
    print(r['name'],r['timing_qualified'],r['control_within_ten_percent'],[(x['old-p50-ns'],x['new-p50-ns'],x['time-paired-wins']) for x in r['runs']])
