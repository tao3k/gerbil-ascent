# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Compiler work observations, separate from uninstrumented latency controls.

GSC input bytes and invocations are exact observations. Import statistics use
the SDK's existing time primitive and its frame/structure corrections. Nested
intervals remain inclusive and must not be added as exclusive allocator/GC
costs. This does not verify the SDK compiler or allocator.
"""
import hashlib
import json
import os
from pathlib import Path
import resource
import re
import shlex
import subprocess
import sys
import time

IMPORT_HOOK = r'''(import :gerbil/expander)
(let ((original (current-expander-module-import))
      (registry (eval 'gx#__module-registry))
      (depth (make-parameter 0))
      (lock (make-mutex))
      (port (open-output-file [path: (getenv "ASCENT_IMPORT_TRACE") append: #t])))
  (current-expander-module-import
   (lambda args
    (let* ((level (depth)) (started (current-jiffy))
           (cached (and (hash-get registry (car args)) #t))
           (allocation (make-f64vector 2))
           (sampled (##get-bytes-allocated! allocation 0))
           (stats (##exec-stats
                    (lambda ()
                      (parameterize ((depth (+ level 1))) (apply original args))))))
      (##get-bytes-allocated! allocation 1)
      (def (stat key) (cdr (assq key stats)))
      (def (ns key) (inexact->exact (floor (* (stat key) 1000000000))))
      (mutex-lock! lock)
      (write (list 'import-work-v3 level (if cached 1 0)
                   (if (string? (car args)) (car args) (object->string (car args)))
                   started (current-jiffy) (jiffies-per-second)
                   (stat 'bytes-allocated) (stat 'nb-gcs)
                   (ns 'user-time) (ns 'sys-time)
                   (ns 'gc-user-time) (ns 'gc-sys-time) (ns 'gc-real-time)
                   (inexact->exact (f64vector-ref allocation 0))
                   (inexact->exact (f64vector-ref allocation 1))) port)
      (newline port) (force-output port)
      (mutex-unlock! lock)
      (stat 'result)))))'''



def file_input(path, contents=None):
    data = path.read_bytes()
    row = {'path': str(path.resolve()), 'bytes': len(data),
           'sha256': hashlib.sha256(data).hexdigest()}
    if contents is not None:
        contents.mkdir(exist_ok=True)
        # Preserve the real expanded input, including source positions and
        # generated names. A digest alone cannot explain compiler work changes.
        blob = contents / row['sha256']
        try:
            with blob.open('xb') as output:
                output.write(data)
        except FileExistsError:
            pass  # Other wrappers may be recording the identical bytes.
    return row


def compiler_stage(record):
    if record['kind'] == 'sdk-helper':
        return 'sdk-' + record['arguments'][0]
    args = record['arguments']
    for flag, stage in (('-c', 'scheme-to-c'), ('-obj', 'c-to-object'), ('-link', 'link-source')):
        if flag in args:
            return stage
    return 'dynamic-or-executable'


def execute_gsc(arguments, helper=False):
    trace = Path(os.environ['ASCENT_GSC_WORK_DIRECTORY'])
    contents = trace.parent / 'inputs'
    inputs = []
    if helper:
        operation = arguments[0].upper()
        names = shlex.split(os.environ.get(f'BUILD_{operation}_INPUT_FILENAMES_PARAM', ''))
        metadata = os.environ.get(f'BUILD_{operation}_META_INFO_FILE_PARAM')
        if metadata:
            names.append(metadata)
        inputs = [file_input(Path(name), contents) for name in dict.fromkeys(names) if Path(name).is_file()]
    option_value = False
    for arg in ([] if helper else arguments):
        if option_value:
            option_value = False
        elif arg in {'-o', '-cc-options', '-ld-options', '-prelude', '-postlude', '-e', '-target', '-cc'}:
            option_value = True
        elif Path(arg).suffix in ('.scm', '.c') and Path(arg).is_file():
            inputs.append(file_input(Path(arg), contents))
    started = time.monotonic_ns()
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    command = str(Path(os.environ['ASCENT_REAL_GSC']).parent / 'gambuild-C') if helper else os.environ['ASCENT_REAL_GSC']
    child_env = os.environ.copy()
    runtime_options = []
    if not helper and child_env.get('ASCENT_SDK_HELPER_DIRECTORY'):
        # Gambit's documented ~~bin runtime override observes internal helper
        # dispatch too. It changes no compiler option or installed SDK file.
        # Pin ~~ too: Gambit otherwise infers the include/lib root from the
        # overridden bin directory, which would change compiler inputs.
        runtime_options = ['-:~~=' + str(Path(command).parent.parent) +
                           ',~~bin=' + child_env['ASCENT_SDK_HELPER_DIRECTORY']]
        child_env['ASCENT_PARENT_GSC_OBSERVER'] = str(os.getpid())
    child = subprocess.Popen([command, *runtime_options, *arguments], env=child_env)
    exit_code = child.wait()
    process_wall_ns = time.monotonic_ns() - started
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    current = all(Path(row['path']).is_file() and file_input(Path(row['path'])) == row for row in inputs)
    record = {'schema': 'ascent.compiler-work.v3', 'kind': 'sdk-helper' if helper else 'gsc',
              'pid': os.getpid(), 'child_pid': child.pid,
              'parent_gsc_observer': os.environ.get('ASCENT_PARENT_GSC_OBSERVER') if helper else None,
              'arguments': arguments, 'runtime_options': runtime_options,
              'inputs': inputs, 'exit_code': exit_code, 'inputs_current': current,
              'process_wall_ns': process_wall_ns,
              'wall_ns': time.monotonic_ns() - started,
              'user_seconds': after.ru_utime - before.ru_utime,
              'system_seconds': after.ru_stime - before.ru_stime,
              'major_faults': after.ru_majflt - before.ru_majflt,
              'max_child_rss_bytes': after.ru_maxrss * (1 if sys.platform == 'darwin' else 1024),
              'input_blocks': after.ru_inblock - before.ru_inblock,
              'output_blocks': after.ru_oublock - before.ru_oublock}
    # One bounded record per process; no concurrent partial text writes.
    (trace / f'{os.getpid()}-{started}.json').write_text(json.dumps(record) + '\n')
    return exit_code if current else 1


def summarize(directory):
    """Fail closed on truncated events. Never sum nested allocation snapshots."""
    from ascent_workbench.preparation_policy import preparation_observation_complete
    phases = {}
    pattern = re.compile(r'\(import-work(-v3)? ([0-9]+) ([01]) ("(?:[^"\\]|\\.)*") '
                         r'([0-9]+) ([0-9]+) ([0-9]+) (-?[0-9]+) ([0-9]+) '
                         r'([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+)(?: (-?[0-9]+) (-?[0-9]+))?\)')
    for phase in ('build', 'prepare', 'prepare-warm'):
        records = [json.loads(p.read_text()) for p in (directory / phase).glob('*.json')]
        for record in records:
            for item in record['inputs']:
                blob = directory / 'inputs' / item['sha256']
                if (not blob.is_file() or blob.stat().st_size != item['bytes']
                        or hashlib.sha256(blob.read_bytes()).hexdigest() != item['sha256']):
                    raise ValueError('missing or damaged expanded compiler input')
        gsc = [r for r in records if r['kind'] == 'gsc']
        helpers = [r for r in records if r['kind'] == 'sdk-helper']
        nested_helpers = [r for r in helpers if r.get('parent_gsc_observer') is not None]
        gsc_by_pid = {str(r['pid']): r for r in gsc if 'pid' in r}
        for helper in nested_helpers:
            if helper['parent_gsc_observer'] not in gsc_by_pid:
                raise ValueError('SDK helper has no containing GSC observation')
        helper_cpu = {}
        for helper in nested_helpers:
            parent = helper['parent_gsc_observer']
            helper_cpu[parent] = helper_cpu.get(parent, 0) + helper['user_seconds'] + helper['system_seconds']
        for parent, cpu in helper_cpu.items():
            outer = gsc_by_pid[parent]
            if cpu > outer['user_seconds'] + outer['system_seconds']:
                raise ValueError('nested SDK helper CPU exceeds containing GSC CPU')
        helper_observed = bool(gsc) and all(r.get('runtime_options') for r in gsc)
        stages = {}
        for record in records:
            stage = compiler_stage(record) if 'arguments' in record else 'legacy-unknown'
            group = stages.setdefault(stage, {'invocations': 0, 'input_bytes': 0, 'inclusive_cpu_seconds': 0})
            group['invocations'] += 1
            group['input_bytes'] += sum(item['bytes'] for item in record['inputs'])
            group['inclusive_cpu_seconds'] += record['user_seconds'] + record['system_seconds']
        imports = []
        trace = directory / f'{phase}-imports.sexp'
        if trace.exists():
            for line in trace.read_text().splitlines():
                match = pattern.fullmatch(line)
                if not match:
                    raise ValueError('incomplete or unsupported import work event')
                version, depth, cached, path, start, end, hz, allocated, gcs, user, system, gcuser, gcsys, gcwall, raw_start, raw_end = match.groups()
                if bool(version) != (raw_start is not None):
                    raise ValueError("allocation snapshot version mismatch")
                start, end, hz = map(int, (start, end, hz))
                if not hz or end < start:
                    raise ValueError('unordered compiler time snapshots')
                imports.append({'depth': int(depth), 'path': json.loads(path),
                                'direct_registry_hit': cached == '1',
                                'wall_ns': (end - start) * 10**9 // hz,
                                'sdk_allocated_bytes': int(allocated), 'gc_count': int(gcs),
                                'raw_counter_start': int(raw_start) if raw_start is not None else None,
                                'raw_counter_end': int(raw_end) if raw_end is not None else None,
                                'raw_counter_decreased': raw_start is not None and int(raw_end) < int(raw_start),
                                'raw_counter_negative': raw_start is not None and min(int(raw_start), int(raw_end)) < 0,
                                'cpu_ns': int(user) + int(system),
                                'gc_cpu_ns': int(gcuser) + int(gcsys), 'gc_wall_ns': int(gcwall)})
        phases[phase] = {
            'gsc_invocations': len(gsc),
            'compiler_stages': stages,
            'largest_gsc_jobs': sorted(gsc,
                key=lambda r: r['user_seconds'] + r['system_seconds'], reverse=True)[:12],
            'gsc_input_bytes': sum(x['bytes'] for r in gsc for x in r['inputs']),
            'gsc_cpu_seconds': sum(r['user_seconds'] + r['system_seconds'] for r in gsc),
            'gsc_major_faults': sum(r['major_faults'] for r in gsc),
            'gsc_failed': sum(r['exit_code'] != 0 for r in gsc),
            'gsc_changed_inputs': sum(not r['inputs_current'] for r in gsc),
            'external_sdk_helper_invocations': len(helpers),
            'external_sdk_helper_failed': sum(r['exit_code'] != 0 for r in helpers),
            'external_sdk_helper_changed_inputs': sum(not r['inputs_current'] for r in helpers),
            'observations_complete': preparation_observation_complete(
                sum(r['exit_code'] != 0 for r in records),
                sum(not r['inputs_current'] for r in records),
                sum(r['sdk_allocated_bytes'] < 0 or r['raw_counter_decreased'] or r['raw_counter_negative']
                    for r in imports), trace.exists()),
            'external_sdk_helper_cpu_seconds': sum(r['user_seconds'] + r['system_seconds'] for r in helpers),
            # GSC RUSAGE_CHILDREN includes nested SDK helpers and native C/link
            # children. These are a subset, never an additive second cost.
            'nested_sdk_helper_invocations': len(nested_helpers),
            'nested_sdk_helper_cpu_seconds': sum(r['user_seconds'] + r['system_seconds'] for r in nested_helpers),
            'internal_helper_observer_enabled': helper_observed,
            'gsc_residual_cpu_seconds': (
                sum(r['user_seconds'] + r['system_seconds'] for r in gsc) - sum(helper_cpu.values())
                if helper_observed else None),
            'cpu_scope': 'GSC inclusive; nested helper CPU is a subset; residual includes observer overhead and is not pure frontend CPU',
            'import_observer_ran': trace.exists(), 'import_requests': len(imports),
            'source_import_requests': sum(r['path'].endswith('.ss') for r in imports),
            'direct_registry_hits': sum(r['direct_registry_hit'] for r in imports),
            'raw_counter_decreases': [r for r in imports if r['raw_counter_decreased']],
            'negative_raw_counters': [r for r in imports if r['raw_counter_negative']],
            'negative_sdk_allocation_estimates': [r for r in imports if r['sdk_allocated_bytes'] < 0],
            'largest_inclusive_imports': sorted(imports,
                key=lambda r: r['sdk_allocated_bytes'], reverse=True)[:12],
            'largest_gc_imports': sorted(imports,
                key=lambda r: r['gc_cpu_ns'], reverse=True)[:12],
            'slowest_imports': sorted(imports,
                key=lambda r: r['wall_ns'], reverse=True)[:12],
            'allocation_scope': 'SDK signed inclusive occupancy-based estimates, not cumulative allocation; raw snapshots include observer work; nested intervals are not summed',
        }
    return {'schema': 'ascent.preparation-work.v3', 'phases': phases,
            'latency_admitted': False, 'compiler_allocator_source_refinement': False}


def install(directory, real_gxi, real_gsc):
    """Install diagnostic wrappers only in a disposable application prefix."""
    directory.mkdir(parents=True, exist_ok=False)
    (directory / 'gsc-records').mkdir()
    entry = Path(__file__).resolve()
    gsc = directory / 'gsc'
    gsc.write_text(f'#!{sys.executable}\nimport runpy\nrunpy.run_path({str(entry)!r}, run_name="__main__")\n')
    gxi = directory / 'gxi'
    gxi.write_text(f'#!{sys.executable}\nimport os,sys\na=sys.argv[1:]\n'
                   'r=[]\nwhile a and a[0].startswith("-:"): r.append(a.pop(0))\n'
                   f'os.execv({str(real_gxi)!r}, [{str(real_gxi)!r}, *r, "-e", {IMPORT_HOOK!r}, *a])\n')
    # Gerbil derives the bundle helper from GERBIL_GSC's directory. Execute
    # the original path, rather than symlinking its script: its $0 locates
    # sibling reuse helpers and participates in the SDK's cache identity.
    original_helper = real_gsc.parent / 'gambuild-C'
    if not original_helper.is_file():
        raise FileNotFoundError(original_helper)
    helper = directory / 'gambuild-C'
    helper.write_text(f'#!{sys.executable}\nimport runpy,sys\nsys.argv.insert(1,"--sdk-helper")\n'
                     f'runpy.run_path({str(entry)!r}, run_name="__main__")\n')
    for path in (gsc, gxi, helper):
        path.chmod(0o755)
    return {'GERBIL_GSC': str(gsc), 'ASCENT_REAL_GSC': str(real_gsc),
            'ASCENT_SDK_HELPER_DIRECTORY': str(directory.resolve()),
            # Package builders execute build.ss through /usr/bin/env gxi;
            # observing only explicit package-prefix gxi calls misses them.
            'PATH': str(directory) + os.pathsep + os.environ.get('PATH', os.defpath),
            'ASCENT_GSC_WORK_DIRECTORY': str(directory / 'gsc-records'),
            'ASCENT_IMPORT_TRACE': str(directory / 'imports.sexp')}


if __name__ == '__main__':
    helper = sys.argv[1:2] == ['--sdk-helper']
    sys.exit(execute_gsc(sys.argv[2:] if helper else sys.argv[1:], helper))
