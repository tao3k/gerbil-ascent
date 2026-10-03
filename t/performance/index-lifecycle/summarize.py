"""Extract scalar summaries; the original S-expression retains every sample."""
import json
import re
import sys
from pathlib import Path
for filename in sys.argv[1:]:
    path = Path(filename)
    pieces = re.split(r'\(name \. ([^)]+)\)', path.read_text())
    results = []
    for name, body in zip(pieces[1::2], pieces[2::2]):
        result = {'name': name}
        for field in ('old-p50-bytes','new-p50-bytes','paired-wins','old-p50-ns','new-p50-ns','old-p95-ns','new-p95-ns','time-paired-wins'):
            result[field] = int(re.search(r'\('+field+r' \. (\d+)\)', body)[1])
        result['speed_ratio'] = result['old-p50-ns']/max(result['new-p50-ns'],1)
        results.append(result)
    path.with_suffix('.json').write_text(json.dumps(results, indent=2)+'\n')
    for result in results:
        print(path.stem, result)
