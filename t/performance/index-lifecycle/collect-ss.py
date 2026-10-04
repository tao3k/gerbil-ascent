"""Preserve each independent original SS outcome, including native exit-zero errors."""
import json
from pathlib import Path
import re
repository = Path(__file__).resolve().parents[3]
root = repository / '.cache/ascent' / Path(__file__).resolve().parent.relative_to(repository)
results=[dict(name='ascent-byods-trrel',exit=1,log='original-ss.log')]
remaining=json.loads((root/'remaining-ss/summary.json').read_text())
assert len(remaining)==16,'remaining original inventory incomplete'
results += [dict(row,log='remaining-ss/'+row['name']+'.log') for row in remaining]
for row in results:
    text=(root/row['log']).read_text()
    row['receipts']=re.findall(r'^\[gerbil-ascent-benchmark\].+$',text,re.M)
    row['failures']=list(dict.fromkeys(re.findall(r'\[Error\]:[^\n]+',text)))
    row['failed_statistics']={key:list(dict.fromkeys(re.findall(r'\('+key+r' \. ([^)]+)\)',text))) for key in ('p50Ns','p95Ns','max_total')}
    if not row['exit']:
        assert re.search(r'^CASE-OK ',text,re.M) and 'MODULE-OK' in text and 'HARNESS-OK' in text and re.search(r'^OK$',text,re.M),row['name']
        assert not re.search(r'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow',text),row['name']
    else:
        assert row['failures'],row['name']
result=dict(entries=17,passed=sum(not r['exit'] for r in results),failed=sum(bool(r['exit']) for r in results),
            uninterrupted_batch_pass=False,results=results)
(root/'original-ss-summary.json').write_text(json.dumps(result,indent=2)+'\n')
print('original SS',result['passed'],'passed',result['failed'],'failed')
for row in results:
    if row['exit']:print(row['name'],row['failures'],row['failed_statistics'])
