#!/usr/bin/env python3
"""Run the Rust-owned mean/provenance reproducer; never infer or admit performance."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess


def artifacts(path):
    expected = {'provenance_load', 'ascent-scheme-worker', 'archive_build'}
    found = {}
    for line in path.read_text().splitlines():
        item = json.loads(line)
        name = item.get('target', {}).get('name')
        if item.get('reason') == 'compiler-artifact' and item.get('executable') and name in expected:
            if name in found:
                raise ValueError('duplicate diagnostic executable: ' + name)
            found[name] = Path(item['executable']).resolve(strict=True)
    if set(found) != expected:
        raise ValueError('incomplete diagnostic build graph')
    return found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--expected-cpus', type=int, required=True)
    args = parser.parse_args()
    if os.cpu_count() != args.expected_cpus:
        raise SystemExit('diagnostic host CPU count differs from its declared cohort')
    binaries = artifacts(args.build)
    args.output.mkdir(parents=True, exist_ok=False)
    root = Path(__file__).resolve().parents[2]
    receipt = {'schema': 'ascent.provenance-load-diagnostic.v1', 'diagnostic_only': True,
               'performance_admitted': False, 'logical_cpus': os.cpu_count(),
               'source_head': subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
               'source_clean': not subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain', '--untracked-files=no'], text=True).strip(),
               'executables': {name: {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()} for name, path in binaries.items()}}
    command = [str(binaries[name]) for name in ['provenance_load', 'ascent-scheme-worker', 'archive_build']]
    environment = dict(os.environ, ASCENT_PROCESS_TRACE='1', RUST_BACKTRACE='1')
    with (args.output / 'stdout').open('w') as stdout, (args.output / 'stderr').open('w') as stderr:
        process = subprocess.Popen(command, cwd=root, env=environment, stdout=stdout, stderr=stderr, start_new_session=True)
        try:
            status = process.wait(timeout=600)
        except subprocess.TimeoutExpired:
            status = 'timeout'
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
    lines = (args.output / 'stderr').read_text().splitlines()
    complete = [line for line in lines if line.startswith('PROVENANCE-LOAD-COMPLETE ')]
    receipt.update(status=status, semantic_checks_complete=status == 0 and len(complete) == 1,
                   completion=complete, command=command)
    (args.output / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if not receipt['semantic_checks_complete']:
        raise SystemExit('mean/provenance load diagnostic failed; original observations retained')


if __name__ == '__main__':
    main()
