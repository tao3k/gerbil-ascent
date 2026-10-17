"""Two standard executables sharing one Scheme module; no compiler interposition."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=False)
gxi = shutil.which('gxi')
identity = subprocess.check_output([gxi, '-e', '(displayln (gerbil-home))'], text=True).strip()
version = subprocess.check_output([gxi, '-v'], text=True).strip()
results = []
for cores in (1, 4):
    root = args.output.resolve() / str(cores)
    root.mkdir()
    (root / 'gerbil.pkg').write_text('(package: release-build-control)\n')
    (root / 'shared.ss').write_text('(export answer answer-code)\n(def answer 42)\n(defrules answer-code () ((_) 0))\n')
    for name in ('first', 'second'):
        (root / (name + '.ss')).write_text('(import "shared")\n(export main)\n(def (main . _) (displayln (+ answer (answer-code))))\n')
    (root / 'build.ss').write_text('(import :std/build-script)\n(defbuild-script \'("shared" (exe: "first") (exe: "second")) optimize: #f)\n')
    env = dict(os.environ, GERBIL_BUILD_CORES=str(cores), GERBIL_PATH=str(root / '.gerbil'))
    env.pop('GERBIL_GSC', None)
    started = time.monotonic()
    with (root / 'build.log').open('w') as log:
        process = subprocess.run([gxi, 'build.ss', 'compile'], cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=120)
    observations = []
    if process.returncode == 0:
        for name in ('first', 'second'):
            result = subprocess.run([str(root / '.gerbil/bin' / name)], capture_output=True, text=True, timeout=10)
            observations.append({'name': name, 'exit': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
    passed = process.returncode == 0 and len(observations) == 2 and all(r['exit'] == 0 and r['stdout'] == '42\n' for r in observations)
    results.append({'cores': cores, 'buildExit': process.returncode, 'seconds': time.monotonic() - started, 'observations': observations, 'passed': passed})
    print(json.dumps(results[-1]), flush=True)
receipt = {'gxi': gxi, 'home': identity, 'version': version, 'results': results}
(args.output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
