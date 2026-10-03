#!/usr/bin/env python3
"""Qualify compiled production code under one exclusive test lease."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SPECIAL = {
    'ascent-binary-program': 't/performance/ascent-binary-program-performance-test.ss',
    'ascent-shortest-candidates': 't/performance/ascent-shortest-candidates-performance-test.ss',
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_manifest():
    # Keep build.ss as the single owner of the production module inventory.
    source = (ROOT / 'build.ss').read_text()
    declaration = re.search(r'\(def gerbil-ascent-library-modules\s+\x27\((.*?)\)\)',
                            source, re.S)
    if not declaration:
        raise ValueError('cannot read production module inventory')
    modules = re.findall(r'"([a-z/-]+)"', declaration[1])
    if not modules or len(set(modules)) != len(modules):
        raise ValueError('invalid production module inventory')
    paths = [name + '.ss' for name in modules]
    paths += ['build.ss', 'gerbil.pkg', 'tools/build-performance-library.ss',
              'tools/performance_execution.py', 'justfile',
              't/performance/ascent-ss-profile.ss', 't/performance/native-library.ss',
              't/performance/ascent-scenario-performance-test.ss', *SPECIAL.values()]
    paths += [str(path.relative_to(ROOT)) for path in
              sorted((ROOT / 't/scenarios/performance').rglob('*.ss'))]
    return modules, {path: digest(ROOT / path) for path in paths}


def dependencies():
    library = Path(os.environ.get('GERBIL_PATH', str(Path.home() / '.gerbil'))) / 'lib'
    return {str(path): digest(path) for path in sorted(library.rglob('*'))
            if path.is_file() and path.suffix in ('.ssi', '.so')
            and 'gerbil-ascent' not in path.relative_to(library).parts}


def run(command, environment):
    # Propagate the parent's real lock descriptor through nested just invocations.
    descriptor = int(environment['ASCENT_TEST_EXCLUSIVE_FD'])
    return subprocess.run(command, cwd=ROOT, env=environment,
                          pass_fds=(descriptor,), check=True)


def verify(snapshot):
    modules, sources = source_manifest()
    if snapshot['sources'] != sources or snapshot['modules'] != modules:
        raise ValueError('production source changed after native qualification build')
    if snapshot['dependencies'] != dependencies():
        raise ValueError('dependency artifacts changed after native qualification build')
    for path, expected in snapshot['artifacts'].items():
        if digest(Path(path)) != expected:
            raise ValueError('native qualification artifact changed: ' + path)
    return modules


def prepare(environment):
    inherited = environment.get('ASCENT_PERFORMANCE_SNAPSHOT')
    if inherited:
        snapshot = json.loads(Path(inherited).read_text())
        verify(snapshot)
        environment['ASCENT_TEST_LIBRARY'] = snapshot['library']
        environment['ASCENT_PERFORMANCE_MODULES'] = str(Path(snapshot['library']).parent / 'modules.sexp')
        print('[native-performance] REUSE verified snapshot ' + inherited, flush=True)
        return
    modules, sources = source_manifest()
    external = dependencies()
    directory = ROOT / '.gerbil/performance-execution'
    directory.mkdir(parents=True, exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix='snapshot-', dir=directory))
    library = workspace / 'lib'
    module_file = workspace / 'modules.sexp'
    module_file.write_text('(' + ' '.join('"' + name + '"' for name in modules) + ')\n')
    environment['ASCENT_TEST_LIBRARY'] = str(library)
    environment['ASCENT_PERFORMANCE_MODULES'] = str(module_file)
    environment['ASCENT_PERFORMANCE_BUILD_DEPS'] = str(workspace / 'build-deps')
    print(f'[native-performance] BUILD modules={len(modules)} library={library}', flush=True)
    run(['timeout', '180s', 'gxi', '-:max-heap=1G,debug=q',
         'tools/build-performance-library.ss'], environment)
    if source_manifest()[1] != sources:
        raise ValueError('production source changed during native qualification build')
    artifacts = {str(path): digest(path) for path in sorted(library.rglob('*'))
                 if path.is_file()}
    artifacts[str(module_file)] = digest(module_file)
    for name in modules:
        if str(library / 'gerbil-ascent' / (name + '.ssi')) not in artifacts:
            raise ValueError('missing compiled production module: ' + name)
    probe = workspace / 'resolution.ss'
    probe.write_text('(import :gerbil/expander)\n' + '\n'.join(
        "(displayln (gx#module-context-path (gx#import-module ':gerbil-ascent/"
        + name + ")))" for name in modules) + '\n')
    environment['GERBIL_LOADPATH'] = str(library) + ':' + str(ROOT) + (
        ':' + environment['GERBIL_LOADPATH'] if environment.get('GERBIL_LOADPATH') else '')
    resolution = subprocess.run(['gxi', '-:max-heap=1G,debug=q', str(probe)],
                                cwd=ROOT, env=environment, text=True, timeout=30,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    paths = resolution.stdout
    (workspace / 'resolution.log').write_text(paths)
    if resolution.returncode:
        print(paths, flush=True)
        resolution.check_returncode()
    expected = [str(library / 'gerbil-ascent' / (name + '.ssi')) for name in modules]
    if paths.splitlines() != expected:
        raise ValueError('production imports did not resolve to the compiled snapshot')
    (workspace / 'resolution.log').write_text(paths)
    snapshot = dict(modules=modules, sources=sources, artifacts=artifacts,
                    dependencies=external,
                    library=str(library), gerbil_path=environment.get('GERBIL_PATH'),
                    dependency_pins=(ROOT / 'gerbil.pkg').read_text())
    receipt = workspace / 'snapshot.json'
    verify(snapshot)
    receipt.write_text(json.dumps(snapshot, indent=2) + '\n')
    environment['ASCENT_PERFORMANCE_SNAPSHOT'] = str(receipt)
    print(f'[native-performance] VERIFIED modules={len(modules)} receipt={receipt}', flush=True)


def main():
    if len(sys.argv) != 2:
        raise ValueError('expected suite or scenario name')
    target = sys.argv[1]
    if target not in ('suite', *SPECIAL) and (not re.fullmatch(r'ascent-[a-z-]+', target) or
            not (ROOT / 't/scenarios/performance' / target / 'scenario.ss').is_file()):
        raise ValueError('unknown performance scenario: ' + target)
    environment = os.environ.copy()
    prepare(environment)
    if target == 'suite':
        run(['just', '_performance'], environment)
    elif target in SPECIAL:
        run(['just', 'test-file', SPECIAL[target]], environment)
    else:
        run(['just', '_performance-scenario', target], environment)
    verify(json.loads(Path(environment['ASCENT_PERFORMANCE_SNAPSHOT']).read_text()))


if __name__ == '__main__':
    main()
