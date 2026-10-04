#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Bind a native test artifact to source bytes; no rule or verdict evaluation."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.cache/ascent/native-library'
BINARY = CACHE / 'dsl-closure'
FREEZE = CACHE / 'dsl-closure-sources.json'
MANIFEST = CACHE / 'dsl-closure.json'


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
        FREEZE.write_text(json.dumps(current, indent=2, sort_keys=True) + '\n')
        print('DSL-SOURCE-FROZEN', flush=True)
        return
    if mode == 'bind':
        if current != json.loads(FREEZE.read_text()):
            raise ValueError('source changed during native DSL compilation')
        receipt = {'schema': 'ascent.dsl-closure-artifact', 'version': 1,
                   'artifactSha256': digest(BINARY), 'sources': current}
        MANIFEST.write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
        print('DSL-ARTIFACT-BOUND', receipt['artifactSha256'], flush=True)
        return
    if mode != 'check':
        raise ValueError('expected freeze, bind or check')
    receipt = json.loads(MANIFEST.read_text())
    if receipt.get('schema') != 'ascent.dsl-closure-artifact' or receipt.get('version') != 1:
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
