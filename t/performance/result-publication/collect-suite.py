"""Collect exact native module and Case completion from the suite receipt."""
import json
import re
import shutil
from pathlib import Path
root = Path(__file__).resolve().parent
match = re.search(r'\[test-suite\] END modules=(\d+) failed=0 receipt=(\S+)', (root/'final-suite.log').read_text())
assert match, 'missing completed suite receipt'
receipt = json.loads(Path(match[2]).read_text())
assert not receipt['failed']
assert sorted(receipt['requested']) == sorted(r['module'] for r in receipt['results'])
assert len(receipt['results']) == int(match[1])
logroot = root/'qualification'
logroot.mkdir(exist_ok=True)
coverage = []
for result in receipt['results']:
    assert result['exit'] == 0
    log = Path(result['log'])
    text = log.read_text()
    cases = re.findall(r'^CASE-OK (.+)$',text,re.M)
    assert cases and len(cases) == len(re.findall(r'^CASE (.+)$',text,re.M)), result['module']
    assert 'MODULE-OK '+result['module'] in text and 'HARNESS-OK' in text
    assert re.search(r'^OK$',text,re.M)
    assert not re.search(r'ERROR (CHECK|CASE|HARNESS|MODULE)|Heap overflow|Stack overflow',text)
    shutil.copyfile(log,logroot/log.name)
    coverage.append(dict(module=result['module'],cases=cases,count=len(cases)))
(root/'suite-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
(root/'suite-coverage.json').write_text(json.dumps(dict(modules=len(coverage),cases=sum(r['count'] for r in coverage),coverage=coverage),indent=2)+'\n')
print('verified modules',len(coverage),'cases',sum(r['count'] for r in coverage))
