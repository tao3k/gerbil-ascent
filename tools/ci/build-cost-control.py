#!/usr/bin/env python3
"""Isolated build controls and independent macOS semantic diagnostics."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import resource
import re
import shutil
import subprocess
import sys
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'workbench/src'))
from ascent_workbench.preparation_admission import qualify
from ascent_workbench.preparation_policy import preparation_non_regression
from ascent_workbench.preparation_work import gcc_ggc_bytes
from ascent_workbench.preparation_work import install as install_work_observers
from ascent_workbench.preparation_work import summarize as summarize_work

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


def compiler_reference(output):
    """One fixed SDK-generated C unit; replay after each complete control only."""
    output.mkdir()
    source = output / 'compiler-reference.scm'
    source.write_text('(declare (block) (standard-bindings) (extended-bindings))\n' +
        ''.join(f'(define (compiler-reference-{i} x) (let loop ((n x) (sum {i})) '
                '(if (<= n 0) sum (loop (- n 1) (+ sum (bitwise-xor n sum))))))\n'
                for i in range(64)))
    sdk = Path(os.environ['GERBIL_HOME'])
    subprocess.run([str(sdk / 'bin/gsc'), '-c', '-o', str(source.with_suffix('.c')), str(source)],
                   check=True, timeout=30, capture_output=True)
    return source.with_suffix('.c')


def measure_compiler_reference(source, output):
    # Do not silently discard A0 or warm an application prefix. This diagnostic
    # follows the complete control; its cost is retained outside phase timings.
    sdk = Path(os.environ['GERBIL_HOME'])
    env = os.environ.copy()
    env.update(GAMBITDIR_INCLUDE=str(sdk / 'include'), GAMBITDIR_LIB=str(sdk / 'lib'),
               BUILD_DYN_INPUT_FILENAMES_PARAM=str(source), BUILD_DYN_META_INFO_FILE_PARAM=str(source),
               BUILD_DYN_OUTPUT_FILENAME_PARAM=str(output),
               BUILD_DYN_CC_OPTIONS_PARAM='-D___SINGLE_HOST_LIMIT=0 -ftime-report -fdiagnostics-format=sarif-file')
    source_before = digest(source)
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    started = time.monotonic_ns()
    with output.with_suffix('.log').open('w') as log:
        result = subprocess.run([str(sdk / 'bin/gambuild-C'), 'dyn'], env=env,
                                stdout=log, stderr=subprocess.STDOUT, timeout=30)
    elapsed = time.monotonic_ns() - started
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    sarif = output.with_name(output.name + '-' + source.name + '.sarif')
    row = {'source_sha256': source_before, 'inputs_current': source_before == digest(source), 'exit_code': result.returncode, 'wall_ns': elapsed,
           'child_usage': {key: getattr(after, key) - getattr(before, key) for key in
                           ['ru_utime', 'ru_stime', 'ru_minflt', 'ru_majflt', 'ru_inblock', 'ru_oublock', 'ru_nvcsw', 'ru_nivcsw']},
           'scope': 'Fixed post-control native compiler calibration; not application work or speedup admission'}
    if result.returncode == 0 and sarif.exists():
        row['gcc_cumulative_ggc_bytes'] = gcc_ggc_bytes(json.loads(sarif.read_text()), source)
    return row


def measure(tree, command, log, env, *, semantic_diagnostics=False):
    stop = threading.Event()
    foreign = []
    audit_errors = []
    process_samples = []
    progress_samples = []
    wall_started = None
    log_offset = 0
    pending_line = ''

    def audit_once():
        rows = []
        columns = 'pid=,ppid=,time=,rss=,comm=' if semantic_diagnostics else 'pid=,ppid=,comm='
        for line in subprocess.check_output(['ps', '-axo', columns], text=True).splitlines():
            parts = line.strip().split(None, 4 if semantic_diagnostics else 2)
            if len(parts) == (5 if semantic_diagnostics else 3):
                rows.append((int(parts[0]), int(parts[1]), parts[-1], parts[2:-1]))
        owned = {os.getpid()}
        for _ in range(16):
            owned.update(pid for pid, parent, _, _ in rows if parent in owned)
        for pid, _, name, _ in rows:
            base = Path(name).name
            if pid not in owned and (base in COMPILERS or base.startswith('gcc-')):
                foreign.append({'pid': pid, 'command': name})
        if semantic_diagnostics and wall_started is not None:
            # Preserve live SELF CPU counters before timeout can kill un-reaped
            # descendants. RUSAGE_CHILDREN alone omits those processes.
            process_samples.append({'observed_seconds': time.monotonic() - wall_started,
                'processes': [{'pid': pid, 'ppid': parent, 'command': name,
                               'self_cpu_time': metrics[0], 'rss_kib': int(metrics[1])}
                              for pid, parent, name, metrics in rows
                              if pid in owned and Path(name).name in
                              COMPILERS | {'gerbil', 'gxtest', 'timeout', 'just'}]})
            observe_progress()

    def observe_progress():
        nonlocal log_offset, pending_line
        if not log.exists():
            return
        with log.open() as stream:
            stream.seek(log_offset)
            chunk = stream.read()
            log_offset = stream.tell()
        lines = (pending_line + chunk).split('\n')
        pending_line = lines.pop()
        elapsed = time.monotonic() - wall_started
        progress_samples.extend({'observed_seconds': elapsed, 'line': line}
                                for line in lines if line.startswith('TEST-'))

    def audit():
        try:
            while not stop.is_set():
                audit_once()
                stop.wait(1)
        except Exception as error:
            audit_errors.append(repr(error))

    thread = threading.Thread(target=audit, daemon=True)
    thread.start()
    reference = reference_cpu()
    usage_before = resource.getrusage(resource.RUSAGE_CHILDREN)
    start_ns = time.monotonic_ns()
    start = time.monotonic()
    wall_started = start
    try:
        with log.open('w') as output:
            result = subprocess.run(command, cwd=tree, env=env, stdout=output, stderr=subprocess.STDOUT)
        wall_ns = time.monotonic_ns() - start_ns
        wall = time.monotonic() - start
    finally:
        stop.set()
        thread.join()
        if semantic_diagnostics:
            try:
                observe_progress()
            except Exception as error:
                audit_errors.append(repr(error))
    usage_after = resource.getrusage(resource.RUSAGE_CHILDREN)
    receipt = {'command': command, 'wall_seconds': wall, 'wall_nanoseconds': wall_ns, 'exit_code': result.returncode,
               'foreign_compilers': foreign, 'audit_errors': audit_errors, 'reference': reference,
               'child_usage_delta': {name: getattr(usage_after, name) - getattr(usage_before, name)
                                     for name in ['ru_utime', 'ru_stime', 'ru_minflt', 'ru_majflt',
                                                  'ru_nvcsw', 'ru_nivcsw', 'ru_inblock', 'ru_oublock']}}
    if semantic_diagnostics:
        receipt['live_process_samples'] = process_samples
        receipt['progress_samples'] = progress_samples
        receipt['diagnostic_resolution_seconds'] = 1
        receipt['child_usage_scope'] = 'reaped children only; not total descendant CPU on timeout'
    text = log.read_text()
    receipt['builder_phases'] = {name: float(value) for name, value in re.findall(
        r'BUILD-TEST-LIBRARY-PHASE ([a-z-]+) wall-seconds=([.0-9]+)', text)}
    total = re.search(r'BUILD-TEST-LIBRARY-OK wall-seconds=([.0-9]+)', text)
    if total:
        receipt['builder_seconds'] = float(total[1])
        receipt['outside_builder_seconds'] = wall - float(total[1])
    log.with_suffix('.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if result.returncode or foreign or audit_errors:
        raise RuntimeError(f'control rejected: {log}; exit={result.returncode}, foreign={len(foreign)}, audit_errors={audit_errors}')
    return receipt


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def test_outputs(tree):
    library = tree / '.gerbil/lib'
    paths = list((library / 'gerbil-ascent/t').rglob('*'))
    paths += list((library / 'static').glob('gerbil-ascent__t__*'))
    return {str(p.relative_to(library)): {'sha256': digest(p), 'mtime_ns': p.stat().st_mtime_ns}
            for p in paths if p.is_file() and p.suffix in {'.ssi', '.scm', '.o1', '.o'}}


def source_semantic_workload(tree, log):
    expected = sorted(str(path.relative_to(tree)) for path in (tree / 't/qualification').glob('*-test.ss'))
    lines = log.read_text().splitlines()
    modules = sorted(line.removeprefix('MODULE-OK ') for line in lines if line.startswith('MODULE-OK '))
    cases = sum(line.startswith('CASE-OK ') for line in lines)
    compiled = [name for name in expected if (tree / '.gerbil/lib/gerbil-ascent' / name).with_suffix('.ssi').exists()]
    if not expected or modules != expected or cases == 0 or compiled:
        raise ValueError('source semantic workload is incomplete or compiled')
    return {'modules': modules, 'cases': cases}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline')
    parser.add_argument('--candidate')
    parser.add_argument('--semantics-only', action='store_true')
    parser.add_argument('--semantic-preparation', action='store_true',
                        help='measure source-Suite preparation instead of the original performance lane')
    parser.add_argument('--semantic-runtime', action='store_true',
                        help='also compare complete source runtime under the original 240-second bound')
    parser.add_argument('--work-only', action='store_true',
                        help='instrument compiler/import work; timings are diagnostic only')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.semantic_preparation and args.semantics_only:
        parser.error('--semantic-preparation is a comparison mode, not a semantic runtime mode')
    if args.work_only and args.semantics_only:
        parser.error('work observations and full semantics are independent modes')
    if args.semantic_runtime and (not args.semantic_preparation or args.work_only or args.semantics_only):
        parser.error('--semantic-runtime requires uninstrumented --semantic-preparation controls')
    root = Path.cwd()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    if args.semantics_only:
        if args.baseline or args.candidate:
            parser.error('--semantics-only does not accept build comparison revisions')
        env = os.environ.copy()
        env['GERBIL_PATH'] = str(root / '.gerbil')
        env['GERBIL_LOADPATH'] = str(root / '.gerbil/lib')
        env['GERBIL_BUILD_CORES'] = '3'
        env['ASCENT_GXTEST_TIMEOUT'] = '240s'
        env.pop('ASCENT_TEST_LIBRARY', None)
        (output / 'inputs.json').write_text(json.dumps({
            'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
            'cores': 3, 'deadline_seconds': 240, 'child_heap': '2G',
            'sdk_receipt': json.loads((Path(os.environ['GERBIL_PREFIX']) /
                                       'gerbil-build-receipt.json').read_text())}, indent=2) + '\n')
        try:
            # This replaces the previous performance-library setup, not any
            # source Suite execution. Retain its complete cost separately so
            # moving dependency work cannot be reported as end-to-end savings.
            measure(root, ['just', 'prepare-semantic-library'],
                    output / 'candidate-prepare-semantics.log', env)
            suite_interfaces = [str(path.relative_to(root))
                                for source in sorted((root / 't/qualification').glob('*-test.ss'))
                                if (path := root / '.gerbil/lib/gerbil-ascent/t/qualification' /
                                    (source.stem + '.ssi')).exists()]
            (output / 'source-suite-interfaces.json').write_text(json.dumps(
                {'compiled_source_suites': suite_interfaces}, indent=2) + '\n')
            if suite_interfaces:
                raise RuntimeError('source qualification unexpectedly compiled Suite carriers')
            measure(root, ['timeout', '240s', 'just', 'test-file', 't/qualification', '2G'],
                    output / 'candidate-semantics.log', env, semantic_diagnostics=True)
        finally:
            batches = root / '.cache/ascent/test-modules'
            if batches.exists():
                shutil.copytree(batches, output / 'semantic-batches')
        print('MACOS-THREE-WORKER-SEMANTICS-OK', flush=True)
        return
    if not args.baseline or not args.candidate:
        parser.error('build comparisons require --baseline and --candidate')
    identities = {name: subprocess.check_output(['git', 'rev-parse', rev + '^{commit}'], text=True).strip()
                  for name, rev in [('baseline', args.baseline), ('candidate', args.candidate)]}
    changed = subprocess.check_output(['git', 'diff', '--name-only', *identities.values()], text=True).splitlines()
    allowed = {'build.ss', 'build-modules.ss', 'justfile', 'interface/build-identity.ss', 'bindings/build-entry.ss', 'bindings/artifact.ss', 't/qualification/scheme-artifact-test.ss',
               'tools/ci/build-cost-control.py', '.github/workflows/build-cost.yml', '.github/workflows/ci.yml',
               't/harness/library-spec.ss', 't/harness/artifact-admission.ss',
               'docs/development/compiler-cost-acceptance-20261019.org',
               't/performance/ascent-scenario-performance-test.ss',
               't/harness/build.ss', 't/harness/test.ss', 't/qualification/ascent-source-import-test.ss',
               'docs/development/link-reuse-acceptance-20261018.org',
               't/qualification/ascent-support-study-output.ss',
               't/qualification/ascent-steensgaard-test.ss',
               't/qualification/ascent-steensgaard-reference.ss',
               't/performance/ascent-steensgaard-performance-test.ss',
               'workbench/src/ascent_workbench/supervision.py',
               'workbench/tests/test_supervision.py',
               'packages/proofs/lean/ExecutionPolicy.lean',
               'packages/proofs/lean/lakefile.lean',
               'packages/proofs/lean/PreparationWork.lean',
               'packages/proofs/lean/CompilerCost.lean',
               'packages/proofs/quint/CompilerCost.qnt',
               'packages/proofs/quint/CompilerPolicy.qnt',
               'rust/ascent-build/src/graph.rs',
               # Preserved Rust-only unit-test relocation. These Scheme-only
               # commands do not compile/execute Rust; independent CI covers it.
               'rust/ascent/src/clues/slices.rs',
               'rust/ascent/tests/unit/clues/capacity.rs',
               'workbench/tests/test_compiler_cost.py',
               'packages/proofs/quint/PreparationPolicy.qnt',
               'packages/proofs/quint/PreparationAdmission.qnt',
               'packages/proofs/quint/PreparationWork.qnt',
               'packages/proofs/quint/PreparationSupport.qnt',
               'packages/proofs/quint/PreparationInterfaces.qnt',
               'workbench/src/ascent_workbench/preparation_policy.py',
               'workbench/src/ascent_workbench/preparation_admission.py',
               'workbench/src/ascent_workbench/preparation_work.py',
               'workbench/src/ascent_workbench/formal.py',
               'workbench/src/ascent_workbench/formal_models.py',
               'workbench/tests/test_formal.py',
               'workbench/tests/test_preparation_admission.py',
               'workbench/tests/test_preparation_work.py',
               't/qualification/fixtures/preparation/unresolved.json'}
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
               'instrumented_work_only': args.work_only,
               'machine': platform.uname()._asdict(),
               'sdk_receipt': json.loads(manifest.read_text()),
               'sdk_binaries': {name: digest(Path(os.environ['GERBIL_HOME']) / 'bin' / name)
                                for name in ['gxi', 'gsc']}, 'controls': []}
    preparation = ['just', 'prepare-semantic-library' if args.semantic_preparation else 'prepare-test-library']
    receipt['preparation_command'] = preparation
    receipt['semantic_runtime_requested'] = args.semantic_runtime
    work_violations = []
    if args.work_only:
        receipt['work_observer_sha256'] = digest(
            root / 'workbench/src/ascent_workbench/preparation_work.py')
    (output / 'inputs.json').write_text(json.dumps(receipt, indent=2) + '\n')
    calibration_started = time.monotonic_ns()
    calibration = compiler_reference(output / 'compiler-calibration')
    receipt['compiler_reference_setup'] = {'wall_ns': time.monotonic_ns() - calibration_started,
                                           'source_sha256': digest(calibration), 'source_bytes': calibration.stat().st_size,
                                           'scope': 'SDK calibration setup outside application phase timings'}
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
        if args.work_only:
            observer = output / f'{name}-work'
            env.update(install_work_observers(observer,
                Path(os.environ['GERBIL_HOME']) / 'bin/gxi',
                Path(os.environ['GERBIL_HOME']) / 'bin/gsc'))
            # just's exact interpreter invocation and resource supervisor remain
            # unchanged. Only this disposable prefix gets an observer entry.
            shutil.copy2(observer / 'gxi', tree / '.gerbil/bin/gxi')
        phases = {}
        for phase, command in [('build', ['just', 'check-policy']),
                               ('prepare', preparation)]:
            if args.work_only:
                phase_trace = observer / phase
                phase_trace.mkdir()
                env['ASCENT_GSC_WORK_DIRECTORY'] = str(phase_trace)
                env['ASCENT_IMPORT_TRACE'] = str(observer / f'{phase}-imports.sexp')
            phases[phase] = measure(tree, command, output / f'{name}-{phase}.log', env)
        before_warm = test_outputs(tree)
        if args.work_only:
            phase_trace = observer / 'prepare-warm'
            phase_trace.mkdir()
            env['ASCENT_GSC_WORK_DIRECTORY'] = str(phase_trace)
            env['ASCENT_IMPORT_TRACE'] = str(observer / 'prepare-warm-imports.sexp')
        phases['prepare-warm'] = measure(tree, preparation,
                                         output / f'{name}-prepare-warm.log', env)
        after_warm = test_outputs(tree)
        changed_outputs = sorted(path for path in before_warm.keys() | after_warm.keys()
                                 if before_warm.get(path) != after_warm.get(path))
        (output / f'{name}-test-outputs.json').write_text(json.dumps(
            {'cold': before_warm, 'warm': after_warm, 'warm_changed': changed_outputs}, indent=2) + '\n')
        if kind == 'candidate' and changed_outputs:
            message = f'unchanged candidate preparation rebuilt test outputs: {changed_outputs}'
            if not args.work_only:
                raise RuntimeError(message)
            # Retain the whole diagnostic ABBA group, then fail. The ordinary
            # wall/currentness gate above still rejects immediately.
            work_violations.append({'control': name, 'error': message})
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
                                    'test_artifacts': inventory, 'warm_changed_outputs': changed_outputs})
        if args.semantic_runtime:
            env['ASCENT_GXTEST_TIMEOUT'] = '240s'
            semantic_log = output / f'{name}-semantics.log'
            try:
                phases['semantics'] = measure(tree,
                    ['timeout', '240s', 'just', 'test-file', 't/qualification', '2G'],
                    semantic_log, env, semantic_diagnostics=True)
            finally:
                batches = tree / '.cache/ascent/test-modules'
                if batches.exists():
                    shutil.copytree(batches, output / f'{name}-semantic-batches')
            workload = source_semantic_workload(tree, semantic_log)
            if 'semantic_workload' in receipt and receipt['semantic_workload'] != workload:
                raise RuntimeError('semantic workload differs between controls')
            receipt['semantic_workload'] = workload
            if digest(library) != binding['librarySha256']:
                raise RuntimeError('semantic run changed the bound production library')
        if args.work_only:
            work = summarize_work(observer)
            (observer / 'summary.json').write_text(json.dumps(work, indent=2) + '\n')
            receipt['controls'][-1]['work'] = work
            for phase, observations in work['phases'].items():
                if not observations['observations_complete']:
                    work_violations.append({'control': name, 'phase': phase,
                                            'error': 'incomplete compiler/helper work, changed inputs, missing imports or negative allocation'})
        receipt['controls'][-1]['compiler_calibration'] = measure_compiler_reference(
            calibration, output / 'compiler-calibration' / (name + '.o1'))
        (output / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(f"CONTROL-OK {name} build={phases['build']['wall_seconds']:.3f} "
              f"prepare={phases['prepare']['wall_seconds']:.3f}", flush=True)
        # Retain logs and receipts; free generated prefixes before the next pair.
        shutil.rmtree(tree)
    ledger_path = root / 't/qualification/fixtures/preparation/unresolved.json'
    if args.work_only:
        # This route must not overwrite or qualify uninstrumented wall controls.
        receipt['work_violations'] = work_violations
        (output / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print('BUILD-WORK-OBSERVATIONS-COMPLETE; timings not admitted', flush=True)
        if work_violations:
            raise RuntimeError('work observations retain currentness failures: ' + json.dumps(work_violations))
        return
    ledger = json.loads(ledger_path.read_text())
    receipt['regression_ledger_sha256'] = digest(ledger_path)
    receipt['performance_admission'] = qualify(receipt['controls'], ledger)
    if args.semantic_runtime:
        totals = {kind: sum(c['phases']['semantics']['wall_nanoseconds'] for c in receipt['controls']
                            if c['kind'] == kind) for kind in ['baseline', 'candidate']}
        receipt['semantic_runtime_comparison'] = {**totals,
            'non_regression': preparation_non_regression(totals['baseline'], totals['candidate']),
            'scope': 'Matched full source runtime; three workers, 240 seconds each; no timing normalization'}

    (output / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('BUILD-COST-MEASUREMENTS-COMPLETE', flush=True)
    if args.semantic_runtime and not receipt['semantic_runtime_comparison']['non_regression']:
        raise RuntimeError('matched source runtime regressed: ' + json.dumps(receipt['semantic_runtime_comparison']))
    if not receipt['performance_admission']['admitted']:
        raise RuntimeError('preparation performance not admitted: ' +
                           json.dumps(receipt['performance_admission'], sort_keys=True))
    print('BUILD-COST-ADMISSION-OK', flush=True)


if __name__ == '__main__':
    main()
