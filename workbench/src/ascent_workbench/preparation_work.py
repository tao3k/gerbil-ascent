# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Compiler work observations, separate from uninstrumented latency controls.

GSC input bytes and invocations are exact observations. Import allocation is
process-wide and inclusive; nested imports must never be summed as exclusive
allocator costs. This does not verify the SDK compiler or allocator.
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
           (before (f64vector-ref (##process-statistics) 7))
           (result (parameterize ((depth (+ level 1))) (apply original args))))
      (mutex-lock! lock)
      (write (list 'import-cost level (if cached 1 0)
                   (if (string? (car args)) (car args) (object->string (car args)))
                   started (current-jiffy) (jiffies-per-second)
                   (inexact->exact before)
                   (inexact->exact (f64vector-ref (##process-statistics) 7))) port)
      (newline port) (force-output port)
      (mutex-unlock! lock)
      result))))'''


def file_input(path):
    data = path.read_bytes()
    return {'path': str(path.resolve()), 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest()}


def execute_gsc(arguments, helper=False):
    inputs = []
    if helper:
        operation = arguments[0].upper()
        names = shlex.split(os.environ.get(f'BUILD_{operation}_INPUT_FILENAMES_PARAM', ''))
        metadata = os.environ.get(f'BUILD_{operation}_META_INFO_FILE_PARAM')
        if metadata:
            names.append(metadata)
        inputs = [file_input(Path(name)) for name in dict.fromkeys(names) if Path(name).is_file()]
    option_value = False
    for arg in ([] if helper else arguments):
        if option_value:
            option_value = False
        elif arg in {'-o', '-cc-options', '-ld-options', '-prelude', '-postlude', '-e', '-target', '-cc'}:
            option_value = True
        elif Path(arg).suffix in ('.scm', '.c') and Path(arg).is_file():
            inputs.append(file_input(Path(arg)))
    started = time.monotonic_ns()
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    command = str(Path(os.environ['ASCENT_REAL_GSC']).parent / 'gambuild-C') if helper else os.environ['ASCENT_REAL_GSC']
    result = subprocess.run([command, *arguments])
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    current = all(Path(row['path']).is_file() and file_input(Path(row['path'])) == row for row in inputs)
    record = {'schema': 'ascent.compiler-work.v1', 'kind': 'sdk-helper' if helper else 'gsc',
              'pid': os.getpid(), 'arguments': arguments,
              'inputs': inputs, 'exit_code': result.returncode, 'inputs_current': current,
              'wall_ns': time.monotonic_ns() - started,
              'user_seconds': after.ru_utime - before.ru_utime,
              'system_seconds': after.ru_stime - before.ru_stime,
              'major_faults': after.ru_majflt - before.ru_majflt,
              'max_child_rss_bytes': after.ru_maxrss * (1 if sys.platform == 'darwin' else 1024),
              'input_blocks': after.ru_inblock - before.ru_inblock,
              'output_blocks': after.ru_oublock - before.ru_oublock}
    # One bounded record per process; no concurrent partial text writes.
    trace = Path(os.environ['ASCENT_GSC_WORK_DIRECTORY'])
    (trace / f'{os.getpid()}-{started}.json').write_text(json.dumps(record) + '\n')
    return result.returncode if current else 1


def summarize(directory):
    """Fail closed on truncated events. Never sum nested allocation snapshots."""
    phases = {}
    pattern = re.compile(r'\(import-cost ([0-9]+) ([01]) ("(?:[^"\\]|\\.)*") '
                         r'([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+)\)')
    for phase in ('build', 'prepare', 'prepare-warm'):
        records = [json.loads(p.read_text()) for p in (directory / phase).glob('*.json')]
        gsc = [r for r in records if r['kind'] == 'gsc']
        helpers = [r for r in records if r['kind'] == 'sdk-helper']
        imports = []
        trace = directory / f'{phase}-imports.sexp'
        if trace.exists():
            for line in trace.read_text().splitlines():
                match = pattern.fullmatch(line)
                if not match:
                    raise ValueError('incomplete or unsupported import work event')
                depth, cached, path, start, end, hz, before, after = match.groups()
                start, end, hz, before, after = map(int, (start, end, hz, before, after))
                if not hz or end < start:
                    raise ValueError('unordered compiler time snapshots')
                imports.append({'depth': int(depth), 'path': json.loads(path),
                                'direct_registry_hit': cached == '1',
                                'wall_ns': (end - start) * 10**9 // hz,
                                'allocator_counter_before': before, 'allocator_counter_after': after,
                                'allocator_counter_delta_bytes': after - before})
        phases[phase] = {
            'gsc_invocations': len(gsc),
            'gsc_input_bytes': sum(x['bytes'] for r in gsc for x in r['inputs']),
            'gsc_cpu_seconds': sum(r['user_seconds'] + r['system_seconds'] for r in gsc),
            'gsc_major_faults': sum(r['major_faults'] for r in gsc),
            'gsc_failed': sum(r['exit_code'] != 0 for r in gsc),
            'gsc_changed_inputs': sum(not r['inputs_current'] for r in gsc),
            'external_sdk_helper_invocations': len(helpers),
            'external_sdk_helper_cpu_seconds': sum(r['user_seconds'] + r['system_seconds'] for r in helpers),
            'import_observer_ran': trace.exists(), 'import_requests': len(imports),
            'source_import_requests': sum(r['path'].endswith('.ss') for r in imports),
            'direct_registry_hits': sum(r['direct_registry_hit'] for r in imports),
            'allocator_counter_decreases': [r for r in imports if r['allocator_counter_delta_bytes'] < 0],
            'largest_inclusive_imports': sorted(imports,
                key=lambda r: r['allocator_counter_delta_bytes'], reverse=True)[:12],
            'allocation_scope': 'inclusive SDK counter snapshots, not exact allocation; nested bytes are not summed',
        }
    return {'schema': 'ascent.preparation-work.v1', 'phases': phases,
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
            'ASCENT_GSC_WORK_DIRECTORY': str(directory / 'gsc-records'),
            'ASCENT_IMPORT_TRACE': str(directory / 'imports.sexp')}


if __name__ == '__main__':
    helper = sys.argv[1:2] == ['--sdk-helper']
    sys.exit(execute_gsc(sys.argv[2:] if helper else sys.argv[1:], helper))
