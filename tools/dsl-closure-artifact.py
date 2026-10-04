#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Bind a native test artifact to source bytes; no rule or verdict evaluation."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.cache/ascent/native-library'
BINARY = CACHE / 'dsl-closure'
FREEZE = CACHE / 'dsl-closure-sources.json'
MANIFEST = CACHE / 'dsl-closure.json'
PENDING = CACHE / 'dsl-closure-pending.json'
RUN = CACHE / 'dsl-closure-run.json'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources():
    paths = subprocess.check_output(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', '*.ss'],
        cwd=ROOT).decode().split('\0')
    paths = sorted(set(p for p in paths if p))
    paths.extend(['justfile', 'tools/dsl-closure-artifact.py', 't/harness/watch_output.py'])
    return {p: digest(ROOT / p) for p in paths}


def main(mode):
    CACHE.mkdir(parents=True, exist_ok=True)
    current = sources()
    if mode == 'freeze':
        token=os.environ.get('ASCENT_DSL_BUILD_TOKEN')
        started=float(os.environ['ASCENT_DSL_BUILD_STARTED'])
        if not token or time.monotonic()-started>=180:
            raise ValueError('missing or expired supervised build identity')
        for path in (MANIFEST,PENDING):
            path.unlink(missing_ok=True)
        RUN.write_text(json.dumps({'token':token,'started':started})+'\n')
        FREEZE.write_text(json.dumps(current, indent=2, sort_keys=True) + '\n')
        print('DSL-SOURCE-FROZEN', flush=True)
        return
    if mode == 'bind':
        run=json.loads(RUN.read_text())
        if run['token']!=os.environ.get('ASCENT_DSL_BUILD_TOKEN'):
            raise ValueError('compile staging owner mismatch')
        if current != json.loads(FREEZE.read_text()):
            raise ValueError('source changed during native DSL compilation')
        receipt = {'schema': 'ascent.dsl-closure-artifact', 'version': 1,
                   'artifactSha256': digest(BINARY), 'sources': current,
                   'buildRun':run['token'],'buildStarted':run['started']}
        if time.monotonic()-run['started']>=180:
            raise ValueError('compile staging exceeded the 180-second build bound')
        PENDING.write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
        print('DSL-ARTIFACT-STAGED', receipt['artifactSha256'], flush=True)
        return
    if mode == 'finalize':
        receipt=json.loads(PENDING.read_text())
        if receipt['buildRun']!=os.environ.get('ASCENT_DSL_BUILD_TOKEN'):
            raise ValueError('compile finalization owner mismatch')
        if receipt['sources']!=current or receipt['artifactSha256']!=digest(BINARY):
            raise ValueError('staged native artifact changed before finalization')
        elapsed=time.monotonic()-receipt['buildStarted']
        if not 0<=elapsed<180:
            raise ValueError('native build exceeded the 180-second bound')
        receipt['compilerExitStatus']=0
        receipt['buildElapsedSeconds']=elapsed
        PENDING.write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
        PENDING.replace(MANIFEST)
        print('DSL-ARTIFACT-BOUND',receipt['artifactSha256'],flush=True)
        return
    if mode != 'check':
        raise ValueError('expected freeze, bind or check')
    receipt = json.loads(MANIFEST.read_text())
    if (receipt.get('schema') != 'ascent.dsl-closure-artifact' or receipt.get('version') != 1
        or receipt.get('compilerExitStatus')!=0 or not 0<=receipt.get('buildElapsedSeconds',180)<180):
        raise ValueError('invalid native DSL artifact binding')
    if receipt['sources'] != current or receipt['artifactSha256'] != digest(BINARY):
        raise ValueError('stale or changed native DSL artifact; run just build-dsl-closure')
    print('DSL-ARTIFACT-VERIFIED', receipt['artifactSha256'], flush=True)


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2:
            raise ValueError('expected freeze, bind or check')
        main(sys.argv[1])
    except (OSError, ValueError, KeyError) as error:
        print('DSL-ARTIFACT-REJECTED', error, file=sys.stderr, flush=True)
        sys.exit(1)
