"""Verify that native qualification changes neither solver nor original budgets."""
import importlib.util
import json
from pathlib import Path
import subprocess

root=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('performance',Path('tools/performance_execution.py'))
runner=importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
commit='5197d6b'
modules,_=runner.source_manifest()
paths=[name+'.ss' for name in modules]
paths += ['build.ss','gerbil.pkg','t/performance/ascent-ss-profile.ss']
paths += [str(p) for p in sorted(Path('t/scenarios/performance').rglob('*.ss'))]
for name in paths:
    original=subprocess.check_output(['git','show',commit+':'+name])
    assert Path(name).read_bytes()==original,name
(root/'baseline-verification.json').write_text(json.dumps(dict(
    baseline=subprocess.check_output(['git','rev-parse',commit],text=True).strip(),
    production_modules=len(modules),unchanged=paths,verified=True),indent=2)+'\n')
print('unchanged production modules',len(modules),'verified files',len(paths))
