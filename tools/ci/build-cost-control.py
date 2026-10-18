#!/usr/bin/env python3
"""Paired cold builds on one dedicated runner; no application output reuse."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import resource
import shutil
import subprocess
import threading
import time

COMPILERS = {'gxi', 'gsc', 'gcc', 'clang', 'clang++', 'cc1', 'cc1plus', 'rustc', 'lean', 'lake', 'cargo'}


def checked(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def reference_cpu():
    # Fixed streaming input, outside the timed build/preparation interval.
    block = bytes(1024 * 1024)
    digest = hashlib.sha256()
    wall, cpu = time.monotonic(), time.process_time()
    for _ in range(2048):
        digest.update(block)
    return {'bytes': len(block) * 2048, 'sha256': digest.hexdigest(),
            'wall_seconds': time.monotonic() - wall,
            'cpu_seconds': time.process_time() - cpu}


def measure(tree, command, log, env):
    stop = threading.Event()
    foreign = []

    def audit():
        while not stop.is_set():
            rows = []
            for line in subprocess.check_output(['ps', '-axo', 'pid=,ppid=,comm='], text=True).splitlines():
                parts = line.strip().split(None, 2)
                if len(parts) == 3:
                    rows.append((int(parts[0]), int(parts[1]), parts[2]))
            owned = {os.getpid()}
            for _ in range(16):
                owned.update(pid for pid, parent, _ in rows if parent in owned)
            for pid, _, name in rows:
                base = Path(name).name
                if pid not in owned and (base in COMPILERS or base.startswith('gcc-')):
                    foreign.append({'pid': pid, 'command': name})
            stop.wait(1)

    thread = threading.Thread(target=audit, daemon=True)
    thread.start()
    reference = reference_cpu()
    usage_before = resource.getrusage(resource.RUSAGE_CHILDREN)
    start = time.monotonic()
    try:
        with log.open('w') as output:
            result = subprocess.run(command, cwd=tree, env=env, stdout=output, stderr=subprocess.STDOUT)
        wall = time.monotonic() - start
    finally:
        stop.set()
        thread.join()
    usage_after = resource.getrusage(resource.RUSAGE_CHILDREN)
    receipt = {'command': command, 'wall_seconds': wall, 'exit_code': result.returncode,
               'foreign_compilers': foreign, 'reference': reference,
               'child_usage_delta': {name: getattr(usage_after, name) - getattr(usage_before, name)
                                     for name in ['ru_utime', 'ru_stime', 'ru_minflt', 'ru_majflt',
                                                  'ru_nvcsw', 'ru_nivcsw']}}
    log.with_suffix('.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if result.returncode or foreign:
        raise RuntimeError(f'control rejected: {log}; exit={result.returncode}, foreign={len(foreign)}')
    return receipt


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path.cwd()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    identities = {name: subprocess.check_output(['git', 'rev-parse', rev + '^{commit}'], text=True).strip()
                  for name, rev in [('baseline', args.baseline), ('candidate', args.candidate)]}
    changed = subprocess.check_output(['git', 'diff', '--name-only', *identities.values()], text=True).splitlines()
    allowed = {'build.ss', 'bindings/build-entry.ss', 't/qualification/scheme-artifact-test.ss',
               'tools/ci/build-cost-control.py', '.github/workflows/build-cost.yml',
               't/harness/library-spec.ss',
               'docs/development/link-reuse-acceptance-20261018.org'}
    if set(changed) - allowed:
        raise RuntimeError(f'unmatched runtime or workload source: {set(changed) - allowed}')
    dependencies = root / '.gerbil'
    if ((dependencies / 'lib/gerbil-ascent').exists()
            or list((dependencies / 'lib/static').glob('gerbil-ascent__*'))
            or list((dependencies / 'bin').glob('libascent*'))
            or list((dependencies / 'bin').glob('ascent-develop*'))):
        raise RuntimeError('dependency seed contains application artifacts')
    manifest = Path(os.environ['GERBIL_PREFIX']) / 'gerbil-build-receipt.json'
    capacity = os.environ['GERBIL_BUILD_CORES']
    receipt = {'identities': identities, 'changed_paths': changed, 'order': [], 'cores': capacity,
               'machine': platform.uname()._asdict(),
               'sdk_receipt': json.loads(manifest.read_text()),
               'sdk_binaries': {name: digest(Path(os.environ['GERBIL_HOME']) / 'bin' / name)
                                for name in ['gxi', 'gsc']}, 'controls': []}
    (output / 'inputs.json').write_text(json.dumps(receipt, indent=2) + '\n')
    # Fixed ABBA order: four fresh application prefixes; never select a fastest run.
    for index, kind in enumerate(['baseline', 'candidate', 'candidate', 'baseline']):
        name = f'{index}-{kind}'
        tree = output / name
        tree.mkdir()
        archive = subprocess.Popen(['git', 'archive', identities[kind]], stdout=subprocess.PIPE)
        try:
            checked('tar', '-xf', '-', '-C', str(tree), stdin=archive.stdout)
        finally:
            archive.stdout.close()
        if archive.wait():
            raise RuntimeError('git archive failed')
        checked('/bin/cp', '-cR', str(dependencies), str(tree / '.gerbil'))
        env = os.environ.copy()
        env['GERBIL_PATH'] = str(tree / '.gerbil')
        for key in ['GERBIL_GSC', 'GERBIL_LOADPATH', 'ASCENT_REAL_GSC', 'ASCENT_GSC_TRACE']:
            env.pop(key, None)
        phases = {}
        for phase, command in [('build', ['just', 'check-policy']),
                               ('prepare', ['just', 'prepare-test-library'])]:
            phases[phase] = measure(tree, command, output / f'{name}-{phase}.log', env)
        prepared = (output / f'{name}-prepare.log').read_text()
        if 'BUILD-TEST-LIBRARY production-rebuilt=0' not in prepared:
            raise RuntimeError('production recompiled during preparation')
        library = tree / '.gerbil/bin/libascent'
        binding = json.loads(library.with_suffix('.json').read_text())
        if binding['librarySha256'] != digest(library):
            raise RuntimeError('library receipt does not match the actual binary')
        if Path(binding['sourceRoot']).resolve() != tree:
            raise RuntimeError('library source root does not match this control')
        program = {key: binding[key] for key in
                   ['schemeSourceSha256', 'runtimeSourceSha256', 'headerSha256']}
        if 'program' in receipt and receipt['program'] != program:
            raise RuntimeError('program inputs differ between controls')
        receipt['program'] = program
        (output / f'{name}-library.json').write_text(json.dumps(binding, indent=2) + '\n')
        receipt['order'].append(name)
        support = tree / '.gerbil/lib/gerbil-ascent/t'
        inventory = {suffix: {'files': len(paths), 'bytes': sum(p.stat().st_size for p in paths)}
                     for suffix in ['.ssi', '.scm', '.o1']
                     for paths in [list(support.rglob('*' + suffix))]}
        receipt['controls'].append({'name': name, 'kind': kind, 'phases': phases,
                                    'test_artifacts': inventory})
        (output / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(f"CONTROL-OK {name} build={phases['build']['wall_seconds']:.3f} "
              f"prepare={phases['prepare']['wall_seconds']:.3f}", flush=True)
        # Retain logs and receipts; free generated prefixes before the next pair.
        shutil.rmtree(tree)
    print('BUILD-COST-CONTROL-OK', flush=True)


if __name__ == '__main__':
    main()
