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
      (seen (make-hash-table-eq))
      (depth (make-parameter 0))
      (lock (make-mutex))
      (port (open-output-file [path: (getenv "ASCENT_IMPORT_TRACE") append: #t])))
  ;; Registry aliases (path/id/library) share context identity. Prime the
  ;; index before observing; only contexts completed after installation count.
  (hash-for-each (lambda (_ context)
                   (when (module-context? context) (hash-put! seen context #t))) registry)
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
      (newline port)
      (when (zero? level)
        (let ((result (stat 'result)))
          ;; A returned context can be reused after native path normalization
          ;; even when the raw request was absent from the registry.
          (write (list 'import-result-work-v1
                       (if (and (module-context? result) (hash-get seen result)) 1 0)) port)
          (newline port)
          (hash-for-each
           (lambda (_ context)
             (when (and (module-context? context) (not (hash-get seen context)))
               (hash-put! seen context #t)
               (write (list 'module-context-work-v1
                            (let (path (module-context-path context))
                              (if (string? path) path (object->string path)))) port)
               (newline port))) registry)))
      (force-output port)
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


def gcc_ggc_bytes(report, source):
    try:
        return _gcc_ggc_bytes(report, source)
    except (AttributeError, IndexError, KeyError, TypeError) as error:
        raise ValueError('malformed GCC report') from error


def _gcc_ggc_bytes(report, source):
    """Read one native GCC cumulative GGC total; never sum nested pass totals."""
    if report.get('version') != '2.1.0' or len(report.get('runs', [])) != 1:
        raise ValueError('unsupported GCC report')
    run = report['runs'][0]
    if not run['tool']['driver']['name'].startswith('GNU C'):
        raise ValueError('unsupported compiler allocation scope')
    invocations = run.get('invocations', [])
    if len(invocations) != 1 or invocations[0].get('executionSuccessful') is not True:
        raise ValueError('incomplete GCC invocation')
    invocation = invocations[0]
    from urllib.parse import unquote, urlparse
    def location_path(uri, base=None):
        parsed = urlparse(uri)
        if parsed.scheme not in ('', 'file') or parsed.netloc:
            raise ValueError('unsupported GCC input URI')
        path = Path(unquote(parsed.path))
        if not path.is_absolute():
            if base is None:
                raise ValueError('relative GCC path has no compiler origin')
            path = base / path
        return path.resolve()

    directory = invocation.get('workingDirectory', {}).get('uri')
    working = location_path(directory) if directory is not None else None
    targets = [a['location'] for a in run.get('artifacts', [])
               if 'analysisTarget' in a.get('roles', [])]
    expected = Path(source).resolve()
    actual = []
    for target in targets:
        base = working
        if 'uriBaseId' in target:
            origin = run.get('originalUriBaseIds', {}).get(target['uriBaseId'])
            if origin is None:
                raise ValueError('unbound GCC input URI base')
            base = location_path(origin['uri'])
        actual.append(location_path(target['uri'], base))
    # Relative compiler arguments belong to the reported compiler directory,
    # never the later summarizer's working directory. Retained reports can be
    # decoded after GSC has deleted its temporary C files.
    arguments = [Path(arg) for arg in invocation.get('arguments', []) if Path(arg).suffix == '.c']
    arguments = [arg.resolve() if arg.is_absolute() else location_path(str(arg), working)
                 for arg in arguments]
    # BEGIN GENERATED PREPARATION ORIGIN
    if actual != [expected] or expected not in arguments:
        raise ValueError('GCC input attribution differs')
    # END GENERATED PREPARATION ORIGIN
    timers = invocation.get('properties', {}).get('gcc/timeReport', {}).get('timevars', [])
    totals = [item.get('elapsed', {}).get('ggc_mem') for item in timers if item.get('name') == 'TOTAL']
    # BEGIN GENERATED PREPARATION GGC
    if len(totals) != 1 or type(totals[0]) is not int or totals[0] < 0:
        raise ValueError('invalid GCC cumulative GGC total')
    # END GENERATED PREPARATION GGC
    return totals[0]


# BEGIN GENERATED PREPARATION COVERAGE
def gcc_ggc_complete(expected, reported, failed, changed, errors):
    return 0 < expected and expected == reported and failed == 0 and changed == 0 and errors == 0
# END GENERATED PREPARATION COVERAGE


# BEGIN GENERATED PREPARATION INPUTS
def gcc_c_inputs(inputs, compiler_input_paths):
    return [row for row in inputs if row['path'] in compiler_input_paths and Path(row['path']).suffix == '.c']
# END GENERATED PREPARATION INPUTS


def compiler_stage(record):
    if record['kind'] == 'sdk-helper':
        return 'sdk-' + record['arguments'][0]
    args = record['arguments']
    for flag, stage in (('-c', 'scheme-to-c'), ('-obj', 'c-to-object'), ('-link', 'link-source')):
        if flag in args:
            return stage
    return 'dynamic-or-executable'


# BEGIN GENERATED PREPARATION CC-OBSERVED
def cc_options_observed(options):
    return isinstance(options, str)
# END GENERATED PREPARATION CC-OBSERVED


def execute_gsc(arguments, helper=False):
    trace = Path(os.environ['ASCENT_GSC_WORK_DIRECTORY'])
    contents = trace.parent / 'inputs'
    inputs = []
    compiler_input_paths = []
    if helper:
        operation = arguments[0].upper()
        names = shlex.split(os.environ.get(f'BUILD_{operation}_INPUT_FILENAMES_PARAM', ''))
        compiler_input_paths = [str(Path(name).resolve()) for name in names if Path(name).is_file()]
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
    working_directory = str(Path.cwd().resolve())
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
    requested_cc_options = (child_env.get(f'BUILD_{arguments[0].upper()}_CC_OPTIONS_PARAM', '')
                            if helper else None)
    gcc_report = None
    gcc_source = None
    if helper:
        c_sources = gcc_c_inputs(inputs, compiler_input_paths)
        output = child_env.get(f'BUILD_{arguments[0].upper()}_OUTPUT_FILENAME_PARAM')
        if len(c_sources) == 1 and output and sum(Path(path).suffix == '.c' for path in compiler_input_paths) == 1:
            gcc_source = c_sources[0]['path']
            # GCC's normal object output uses a different auxiliary basename
            # from an unknown bundle extension (.o1). Link metadata is not a C
            # compiler input and must never manufacture an expected report.
            destination = Path(output).resolve()
            gcc_report = (destination.with_suffix('.c.sarif') if destination.suffix == '.o' else
                          destination.with_name(destination.name + '-' + Path(gcc_source).name + '.sarif'))
            # The native compiler writes this diagnostic beside its own output.
            # Never add diagnostics to the immutable SDK installation.
            if gcc_report.is_relative_to(Path(command).parent.parent):
                gcc_report = None
            else:
                gcc_report.unlink(missing_ok=True)
                key = f'BUILD_{arguments[0].upper()}_CC_OPTIONS_PARAM'
                child_env[key] = child_env.get(key, '') + ' -ftime-report -ftime-report-details -fdiagnostics-format=sarif-file'
    child = subprocess.Popen([command, *runtime_options, *arguments], env=child_env)
    exit_code = child.wait()
    process_wall_ns = time.monotonic_ns() - started
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    outputs = []
    if not helper and exit_code == 0:
        for path in compiler_output_paths(arguments, inputs, working_directory):
            if path.is_file():
                outputs.append(file_input(path, contents))
    current = all(Path(row['path']).is_file() and file_input(Path(row['path'])) == row for row in inputs)
    record = {'schema': 'ascent.compiler-work.v4', 'kind': 'sdk-helper' if helper else 'gsc',
              'pid': os.getpid(), 'child_pid': child.pid,
              'parent_gsc_observer': os.environ.get('ASCENT_PARENT_GSC_OBSERVER') if helper else None,
              'arguments': arguments, 'runtime_options': runtime_options, 'working_directory': working_directory,
              'requested_cc_options': requested_cc_options,
              'effective_cc_options': (child_env.get(f'BUILD_{arguments[0].upper()}_CC_OPTIONS_PARAM', '') if helper else None),
              'started_ns': started, 'finished_ns': time.monotonic_ns(), 'outputs': outputs,
              'inputs': inputs, 'compiler_input_paths': compiler_input_paths if helper else None,
              'exit_code': exit_code, 'inputs_current': current,
              'process_wall_ns': process_wall_ns,
              'wall_ns': time.monotonic_ns() - started,
              'user_seconds': after.ru_utime - before.ru_utime,
              'system_seconds': after.ru_stime - before.ru_stime,
              'major_faults': after.ru_majflt - before.ru_majflt,
              'max_child_rss_bytes': after.ru_maxrss * (1 if sys.platform == 'darwin' else 1024),
              'input_blocks': after.ru_inblock - before.ru_inblock,
              'output_blocks': after.ru_oublock - before.ru_oublock}
    if gcc_report is not None:
        record['gcc_report_expected'] = True
        try:
            observed = file_input(gcc_report, contents)
            record['gcc_ggc_bytes'] = gcc_ggc_bytes(json.loads(gcc_report.read_text()), gcc_source)
            record['gcc_report'] = observed
            record['gcc_source'] = gcc_source
        except (OSError, ValueError, KeyError, TypeError) as error:
            record['gcc_allocation_error'] = str(error)
    # One bounded record per process; no concurrent partial text writes.
    (trace / f'{os.getpid()}-{started}.json').write_text(json.dumps(record) + '\n')
    return exit_code if current else 1


# BEGIN GENERATED PREPARATION PARENT
# Paths are normalized by file_input; SDK code generation remains a premise.
def generated_scheme_input(helper, parent):
    if helper.get('parent_gsc_observer') != str(parent.get('pid')):
        return None
    sources = gcc_c_inputs(helper['inputs'], helper.get('compiler_input_paths', []))
    if len(sources) != 1:
        return None
    expected = str(Path(sources[0]['path']).with_suffix('.scm'))
    matches = [item for item in parent['inputs'] if item['path'] == expected]
    return matches[0] if len(matches) == 1 else None
# END GENERATED PREPARATION PARENT



# BEGIN GENERATED PREPARATION PRODUCER
def producer_eligible(success, current, ordered, same_content, unique):
    return success and current and ordered and same_content and unique
# END GENERATED PREPARATION PRODUCER

# BEGIN GENERATED PREPARATION OUTPUT-TARGET
def c_output_target(arguments):
    return ('-target' not in arguments or arguments[arguments.index('-target') + 1] == 'C') and '-flat' not in arguments
# END GENERATED PREPARATION OUTPUT-TARGET


# BEGIN GENERATED PREPARATION JOB-ALLOCATION
def compiler_allocation_total(jobs):
    return sum(job['gcc_ggc_bytes'] for job in jobs)
# END GENERATED PREPARATION JOB-ALLOCATION



# BEGIN GENERATED PREPARATION SOURCE-COVERAGE
def source_cost_coverage(expected, attributed):
    return expected == attributed
# END GENERATED PREPARATION SOURCE-COVERAGE


def compiler_output_paths(arguments, inputs, directory=None):
    """Pinned GSC C-target output contract, checked with released SDK fixtures."""
    if not c_output_target(arguments):
        return []
    explicit = Path(arguments[arguments.index('-o') + 1]) if '-o' in arguments else None
    if explicit is not None and not explicit.is_absolute():
        if directory is None:
            return []  # A summary process's current directory is not compiler origin.
        explicit = Path(directory) / explicit
    explicit = explicit.resolve() if explicit is not None else None
    schemes = [Path(item['path']) for item in inputs if Path(item['path']).suffix == '.scm']
    if '-link' in arguments and inputs:
        link = explicit or Path(inputs[-1]['path']).with_name(Path(inputs[-1]['path']).stem + '_.c')
        generated = [path.with_suffix('.c') for path in schemes]
        if link.suffix != '.c' or link in generated or any(path in generated for path in
                [Path(item['path']) for item in inputs if Path(item['path']).suffix == '.c']):
            return []
        return list(dict.fromkeys(generated + [link]))
    if '-c' in arguments and explicit is not None and explicit.suffix == '.c' and len(schemes) == 1:
        return [explicit]
    return []


def producer_output_sources(producer, output):
    expected = compiler_output_paths(producer['arguments'], producer['inputs'], producer.get('working_directory'))
    if Path(output['path']) not in expected or output not in producer.get('outputs', []):
        return None
    schemes = [item for item in producer['inputs'] if Path(item['path']).suffix == '.scm']
    if '-link' not in producer['arguments']:
        return {'operation': 'scheme-to-c', 'inputs': schemes} if len(schemes) == 1 else None
    matches = [item for item in schemes if str(Path(item['path']).with_suffix('.c')) == output['path']]
    if len(matches) == 1:
        return {'operation': 'scheme-to-c', 'inputs': matches}
    if matches:
        return None
    # The link source depends on actual C inputs, including those emitted from
    # Scheme inside this same GSC invocation. Keep one cost node, not one per edge.
    generated = []
    for scheme in schemes:
        path = str(Path(scheme['path']).with_suffix('.c'))
        candidates = [item for item in producer['outputs'] if item['path'] == path]
        if len(candidates) != 1:
            return None
        generated.extend(candidates)
    direct = [item for item in producer['inputs'] if Path(item['path']).suffix == '.c']
    sources = direct + generated
    if not sources or output in sources:
        return None
    return {'operation': 'link-source', 'inputs': sources}


# BEGIN GENERATED PREPARATION OUTPUT-PUBLICATION
def ordered_publication_eligible(same_path, disjoint, unique_latest):
    return same_path and disjoint and unique_latest
# END GENERATED PREPARATION OUTPUT-PUBLICATION


def generated_source_producer(helper, parent, producers):
    """Join actual C bytes to one prior output node, including linker DAGs."""
    if helper.get('parent_gsc_observer') != str(parent.get('pid')):
        return None
    sources = gcc_c_inputs(helper['inputs'], helper.get('compiler_input_paths', []))
    if len(sources) != 1 or sources[0] not in parent['inputs']:
        return None
    target = sources[0]
    candidates = []
    for producer in producers:
        outputs = [item for item in producer.get('outputs', [])
                   if all(item.get(k) == target.get(k) for k in ('sha256', 'bytes'))]
        ordered = ('finished_ns' in producer and 'started_ns' in parent
                   and producer['finished_ns'] <= parent['started_ns'])
        origin = producer_output_sources(producer, outputs[0]) if len(outputs) == 1 else None
        if producer_eligible(producer['exit_code'] == 0, producer['inputs_current'],
                             ordered, len(outputs) == 1, origin is not None):
            candidates.append({'producer_pid': producer['pid'], 'source_inputs': origin['inputs'],
                               'operation': origin['operation'], 'generated_c_output': outputs[0],
                               'started_ns': producer.get('started_ns'), 'finished_ns': producer['finished_ns']})
    if len(candidates) == 1:
        return candidates[0]
    if not candidates:
        return None
    latest = max(candidates, key=lambda item: item['finished_ns'])
    others = [item for item in candidates if item is not latest]
    # Repeated -link calls publish the same static path. Resolve only ordered,
    # nonoverlapping writes to that path; copied alternatives remain ambiguous.
    same_path = all(item['generated_c_output']['path'] == target['path'] for item in candidates)
    disjoint = (latest['started_ns'] is not None and
                all(item['finished_ns'] <= latest['started_ns'] for item in others))
    unique = all(item['finished_ns'] < latest['finished_ns'] for item in others)
    return latest if ordered_publication_eligible(same_path, disjoint, unique) else None


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
            for item in record['inputs'] + record.get('outputs', []):
                blob = directory / 'inputs' / item['sha256']
                if (not blob.is_file() or blob.stat().st_size != item['bytes']
                        or hashlib.sha256(blob.read_bytes()).hexdigest() != item['sha256']):
                    raise ValueError('missing or damaged expanded compiler input')
        gsc = [r for r in records if r['kind'] == 'gsc']
        helpers = [r for r in records if r['kind'] == 'sdk-helper']
        nested_helpers = [r for r in helpers if r.get('parent_gsc_observer') is not None]
        gsc_by_pid = {str(r['pid']): r for r in gsc if 'pid' in r}
        if len(gsc_by_pid) != len(gsc):
            raise ValueError('ambiguous containing GSC observation')
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
        gcc_reports = [r for r in helpers if r.get('gcc_report_expected')]
        gcc_errors = [r.get('gcc_allocation_error', 'missing GCC report') for r in gcc_reports
                      if 'gcc_report' not in r]
        for record in gcc_reports:
            if 'gcc_report' in record:
                report = record['gcc_report']
                blob = directory / 'inputs' / report['sha256']
                if (not blob.is_file() or hashlib.sha256(blob.read_bytes()).hexdigest() != report['sha256']
                        or gcc_ggc_bytes(json.loads(blob.read_text()), record['gcc_source']) != record['gcc_ggc_bytes']):
                    raise ValueError('damaged GCC allocation report')
        gcc_jobs = [r for r in helpers if gcc_c_inputs(r['inputs'],
                    r.get('compiler_input_paths', [i['path'] for i in r['inputs']]))]
        gcc_complete = gcc_ggc_complete(len(gcc_jobs), len(gcc_reports),
                                        sum(r['exit_code'] != 0 for r in gcc_jobs),
                                        sum(not r['inputs_current'] for r in gcc_jobs), len(gcc_errors))
        source_costs = []
        for helper in gcc_jobs:
            parent = gsc_by_pid.get(helper.get('parent_gsc_observer'))
            scheme = generated_scheme_input(helper, parent) if parent else None
            producer = generated_source_producer(helper, parent, gsc) if parent and scheme is None else None
            if producer is not None:
                roots = producer['source_inputs']
                scheme = roots[0] if len(roots) == 1 and Path(roots[0]['path']).suffix == '.scm' else None
            source_costs.append({
                'helper_pid': helper.get('pid'),
                'parent_gsc_observer': helper.get('parent_gsc_observer'),
                'actual_c_inputs': gcc_c_inputs(helper['inputs'], helper.get('compiler_input_paths', [])),
                'generated_scheme_input': scheme,
                'generated_source_producer': producer,
                'source_inputs': producer['source_inputs'] if producer else ([scheme] if scheme else []),
                'cpu_seconds': helper['user_seconds'] + helper['system_seconds'],
                'process_wall_ns': helper.get('process_wall_ns'),
                'max_child_rss_bytes': helper.get('max_child_rss_bytes'),
                'major_faults': helper.get('major_faults'),
                'input_blocks': helper.get('input_blocks'),
                'output_blocks': helper.get('output_blocks'),
                'gcc_cumulative_ggc_bytes': helper.get('gcc_ggc_bytes'),
                'gcc_report': helper.get('gcc_report'),
                'requested_cc_options': helper.get('requested_cc_options'),
            })
        source_complete = source_cost_coverage(len(source_costs), sum(bool(row['source_inputs']) for row in source_costs))
        imports = []
        completed_contexts = []
        context_results = []
        trace = directory / f'{phase}-imports.sexp'
        if trace.exists():
            for line in trace.read_text().splitlines():
                context = re.fullmatch(r'\(module-context-work-v1 ("(?:[^"\\]|\\.)*")\)', line)
                if context:
                    completed_contexts.append(json.loads(context[1]))
                    continue
                result = re.fullmatch(r'\(import-result-work-v1 ([01])\)', line)
                if result:
                    context_results.append(result[1] == '1')
                    continue
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
                                'start_tick': start, 'end_tick': end, 'clock_hz': hz,
                                'direct_registry_hit': cached == '1',
                                'wall_ns': (end - start) * 10**9 // hz,
                                'sdk_allocated_bytes': int(allocated), 'gc_count': int(gcs),
                                'raw_counter_start': int(raw_start) if raw_start is not None else None,
                                'raw_counter_end': int(raw_end) if raw_end is not None else None,
                                'raw_counter_decreased': raw_start is not None and int(raw_end) < int(raw_start),
                                'raw_counter_negative': raw_start is not None and min(int(raw_start), int(raw_end)) < 0,
                                'cpu_ns': int(user) + int(system),
                                'gc_cpu_ns': int(gcuser) + int(gcsys), 'gc_wall_ns': int(gcwall)})
        if (completed_contexts and not context_results) or (context_results and
                len(context_results) != sum(r['depth'] == 0 for r in imports)):
            raise ValueError('incomplete top-level context observations')
        roots = sorted((r for r in imports if r['depth'] == 0
                        and r['path'].startswith('t/qualification/')
                        and r['path'].endswith('-test.ss')), key=lambda r: r['start_tick'])
        if any(a['clock_hz'] != b['clock_hz'] or a['end_tick'] > b['start_tick']
               for a, b in zip(roots, roots[1:])):
            raise ValueError('overlapping qualification root observations')
        root_work = {key: sum(r[key] for r in roots)
                     for key in ['wall_ns', 'cpu_ns', 'gc_cpu_ns', 'gc_wall_ns', 'gc_count']}
        root_work.update(roots=len(roots), observed=bool(roots),
                         scope='Nonoverlapping outer qualification imports only; nested imports not summed; not total preparation or allocation')
        phases[phase] = {
            'qualification_root_work': root_work,
            'compiler_source_costs': source_costs,
            'compiler_options_observed': bool(gcc_jobs) and all(cc_options_observed(row.get('requested_cc_options')) for row in gcc_jobs),
            'compiler_options_scope': 'Observed SDK per-invocation extra C options; immutable SDK supplies base flags; not inferred from the parent or metadata',
            'source_cost_complete': source_complete,
            'source_attributed_jobs': sum(bool(row['source_inputs']) for row in source_costs),
            'generated_scheme_attributed_jobs': sum(r['generated_scheme_input'] is not None for r in source_costs),
            'generated_scheme_unattributed_cpu_seconds': sum(r['cpu_seconds'] for r in source_costs
                                                            if r['generated_scheme_input'] is None),
            'compiler_source_cost_scope': 'Exclusive native helper costs by actual C input; generated inputs via unique containing Scheme or prior successful content-identical C output node, including linker DAGs; not original DSL source or macro-expansion equivalence',
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
                    for r in imports), trace.exists()) and not gcc_errors and source_complete,
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
            'context_observer_ran': bool(context_results),
            'top_level_context_reuses': sum(context_results),
            'completed_module_contexts': completed_contexts,
            'completed_source_contexts': sum(p.endswith('.ss') for p in completed_contexts),
            'completed_interface_contexts': sum(p.endswith('.ssi') for p in completed_contexts),
            'gcc_cumulative_ggc_bytes': compiler_allocation_total(gcc_reports) if gcc_complete else None,
            'gcc_cumulative_ggc_observed': gcc_complete,
            'gcc_allocation_jobs': len(gcc_reports),
            'gcc_allocation_errors': gcc_errors,
            'gcc_allocation_scope': 'Native GCC cumulative GGC allocations only; excludes non-GGC malloc and Scheme VM allocations; nested passes not summed',
            'cumulative_allocation_bytes': None,
            'cumulative_allocation_observed': False,
            'context_scope': 'new registered context identities at successful top-level import boundaries; aliases deduplicated; failed or unregistered expansions and pre-installation work excluded; not per-macro expansion counts',
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
    return {'schema': 'ascent.preparation-work.v4', 'phases': phases,
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
