#!/usr/bin/env python3
"""Process isolation for qualified tests; std/test still owns Case execution."""
import argparse
import concurrent.futures
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parent.parent
# Explicit admission: these fixtures compare values, not elapsed-time samples.
# Unknown modules and performance recipes remain exclusive. Zero-timeout and
# nonnegative timing metadata assertions do not measure performance thresholds.
# Module processes isolate callbacks, globals, sessions, and native GC state.
PARALLEL_MODULES = frozenset({
    't/qualification/ascent-aggregate-program-test.ss',
    't/qualification/ascent-binary-program-test.ss',
    't/qualification/ascent-binding-program-test.ss',
    't/qualification/ascent-binding-test.ss',
    't/qualification/ascent-byods-index-test.ss',
    't/qualification/ascent-byods-invariants-test.ss',
    't/qualification/ascent-candidate-description-test.ss',
    't/qualification/ascent-closure-candidates-test.ss',
    't/qualification/ascent-contract-union-test.ss',
    't/qualification/ascent-eqrel-program-test.ss',
    't/qualification/ascent-finite-evidence-test.ss',
    't/qualification/ascent-index-lifecycle-test.ss',
    't/qualification/ascent-index-program-test.ss',
    't/qualification/ascent-invalid-program-test.ss',
    't/qualification/ascent-lattice-program-test.ss',
    't/qualification/ascent-materialization-test.ss',
    't/qualification/ascent-module-program-test.ss',
    't/qualification/ascent-multi-frontier-test.ss',
    't/qualification/ascent-poo-primitives-test.ss',
    't/qualification/ascent-positive-nonmembership-test.ss',
    't/qualification/ascent-positive-plan-test.ss',
    't/qualification/ascent-positive-provenance-test.ss',
    't/qualification/ascent-reasoning-library-test.ss',
    't/qualification/ascent-request-projection-test.ss',
    't/qualification/ascent-result-publication-test.ss',
    't/qualification/ascent-scc-summary-test.ss',
    't/qualification/ascent-set-batch-test.ss',
    't/qualification/ascent-set-emit-test.ss',
    't/qualification/ascent-set-size-test.ss',
    't/qualification/ascent-set-source-test.ss',
    't/qualification/ascent-size-test.ss',
    't/qualification/ascent-source-admission-test.ss',
    't/qualification/ascent-strata-test.ss',
    't/qualification/ascent-stratified-proof-test.ss',
    't/qualification/ascent-syntax-test.ss',
    't/qualification/ascent-table-expression-test.ss',
    't/qualification/ascent-temporal-lens-test.ss',
    't/qualification/ascent-timeout-test.ss',
    't/qualification/ascent-timing-test.ss',
    't/qualification/ascent-workspace-test.ss',
    't/qualification/scheme-library-contract-test.ss',
    't/qualification/scheme-native-integration-test.ss',
    't/qualification/scheme-native-language-test.ss',
    't/qualification/scheme-native-reduction-test.ss',
    't/qualification/scheme-operator-retained-test.ss',
    't/qualification/scheme-operator-test.ss',
    't/qualification/scheme-relational-test.ss',
})


# These Cases enforce wall-clock budgets; each requires an uncontended lane.
EXCLUSIVE_REASONS = {
    't/qualification/ascent-mutual-program-test.ss': 'custom 15-second Case budget',
    't/qualification/ascent-observability-test.ss': 'duration and sampling contract',
    't/qualification/ascent-rule-program-test.ss': 'custom 2/5-second Case budgets',
}


def resolve_jobs(override):
    if override not in (None, 'auto'):
        selected = int(override)
    else:
        # ASP owns parsing GERBIL_BUILD_CORES and the native host CPU fallback.
        source = Path(__file__).with_name('native_test_capacity.ss')
        selected = int(subprocess.check_output(
            ['gxi', str(source)], cwd=ROOT, text=True, timeout=15).strip())
    if selected < 1:
        raise ValueError('jobs must be a positive integer')
    return selected


def canonical_module(value):
    return str((ROOT / value).resolve().relative_to(ROOT.resolve()))


def acquire(handle, mode, label):
    started = time.monotonic()
    next_notice = started + 5
    while True:
        try:
            fcntl.flock(handle, mode | fcntl.LOCK_NB)
            return
        except BlockingIOError:
            now = time.monotonic()
            if now - started >= 120:
                raise TimeoutError(f'test lane wait exceeded 120s: {label}')
            if now >= next_notice:
                print(f'[test-lane] WAIT {label} ({now-started:.0f}s)', flush=True)
                next_notice = now + 5
            time.sleep(0.1)


def interrupted(signum, frame):
    raise KeyboardInterrupt


def run(args):
    command = args.command
    if command and command[0] == '--':
        command = command[1:]
    if not command:
        raise ValueError('missing command')
    shared = args.module is not None and canonical_module(args.module) in PARALLEL_MODULES
    lane = 'parallel-semantics' if shared else 'exclusive'
    directory = ROOT / '.gerbil/test-execution'
    directory.mkdir(parents=True, exist_ok=True)
    lock_path = directory / 'lane.lock'
    inherited = os.environ.get('ASCENT_TEST_EXCLUSIVE_FD')
    if inherited:
        descriptor = int(inherited)
        # An environment flag alone cannot bypass acquisition. The parent must
        # have passed its open lock descriptor through exec to this child.
        held = os.fstat(descriptor)
        actual = lock_path.stat()
        if (held.st_dev, held.st_ino) != (actual.st_dev, actual.st_ino):
            raise ValueError('invalid inherited exclusive test lease')
        return run_child(command, os.environ.copy(), descriptor, lane)
    # Never unlink this file: all callers must lock the same inode.
    with lock_path.open('a') as lock:
        acquire(lock, fcntl.LOCK_SH if shared else fcntl.LOCK_EX, lane)
        print(f'[test-lane] START {lane} {args.module or command[0]}', flush=True)
        environment = os.environ.copy()
        if not shared:
            environment['ASCENT_TEST_EXCLUSIVE_FD'] = str(lock.fileno())
        return run_child(command, environment, lock.fileno(), lane)


def run_child(command, environment, descriptor, lane):
    child = subprocess.Popen(command, cwd=ROOT, start_new_session=True,
                             env=environment, pass_fds=(descriptor,))
    started = time.monotonic()
    try:
        while True:
            try:
                status = child.wait(timeout=5)
                print(f'[test-lane] END {lane} exit={status}', flush=True)
                return status if status >= 0 else 128 - status
            except subprocess.TimeoutExpired:
                print(f'[test-lane] RUNNING {lane} ({time.monotonic()-started:.0f}s)', flush=True)
    finally:
        stop_child(child)


def signal_child(child, signum):
    try:
        os.killpg(child.pid, signum)
    except ProcessLookupError:
        pass


def stop_child(child, deadline=None):
    """Reap a worker even if it ignores TERM; never wait unbounded on cancellation."""
    if child.poll() is None:
        signal_child(child, signal.SIGTERM)
        try:
            child.wait(timeout=5 if deadline is None else max(0, deadline-time.monotonic()))
        except subprocess.TimeoutExpired:
            signal_child(child, signal.SIGKILL)
            child.wait()


def execute_modules(files, jobs, lane):
    """One lifecycle for both phases; each module retains its native process."""
    receipts = ROOT / '.gerbil/test-execution' / f'{lane}-{time.time_ns()}'
    receipts.mkdir(parents=True)
    children = set()
    children_gate = threading.Lock()
    cancelled = threading.Event()
    results = []
    workers = min(jobs, len(files))
    started = time.monotonic()
    print(f'[{lane}-test] PLAN configured-jobs={jobs} workers={workers} modules={len(files)}', flush=True)

    def execute(path):
        log = receipts / (Path(path).stem + '.log')
        began = time.monotonic()
        with log.open('w') as output:
            with children_gate:
                if cancelled.is_set():
                    return None
                child = subprocess.Popen(['just', 'test-file', path], cwd=ROOT,
                                         stdout=output, stderr=subprocess.STDOUT,
                                         start_new_session=True)
                children.add(child)
            try:
                status = child.wait()
            finally:
                with children_gate:
                    children.discard(child)
        result = dict(module=path, exit=status, seconds=time.monotonic()-began,
                      log=str(log), lane=lane)
        print(f'[{lane}-test] END {path} exit={status} log={log}', flush=True)
        return result

    def save():
        (receipts / 'summary.json').write_text(json.dumps(dict(
            configured_jobs=jobs, workers=workers, requested=files,
            cancelled=cancelled.is_set(), seconds=time.monotonic()-started,
            results=sorted(results, key=lambda row: row['module'])), indent=2)+'\n')

    if not files:
        save()
        return results
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        pending = set()
        try:
            for path in files:
                pending.add(pool.submit(execute, path))
            while pending:
                done, pending = concurrent.futures.wait(
                    pending, timeout=5, return_when=concurrent.futures.FIRST_COMPLETED)
                for future in done:
                    result = future.result()
                    if result is not None:
                        results.append(result)
                if pending:
                    print(f'[{lane}-test] RUNNING remaining={len(pending)} logs={receipts}', flush=True)
        except BaseException:
            with children_gate:
                cancelled.set()
                active = list(children)
            for future in pending:
                future.cancel()
            # Signal every worker first, then reap; TERM-resistant workers cannot
            # keep the pool alive after the coordinator is interrupted.
            for child in active:
                if child.poll() is None:
                    signal_child(child, signal.SIGTERM)
            deadline = time.monotonic() + 5
            for child in active:
                stop_child(child, deadline)
            raise
        finally:
            save()
    return results


def parallel(args):
    files = [canonical_module(value) for value in
             (args.files if args.files else sorted(PARALLEL_MODULES))]
    if len(set(files)) != len(files) or any(value not in PARALLEL_MODULES for value in files):
        raise ValueError('parallel requires unique, explicitly admitted semantic modules')
    if args.jobs < 1:
        raise ValueError('jobs must be a positive integer')
    return int(any(row['exit'] != 0 for row in execute_modules(files, args.jobs, 'parallel')))


def suite(args):
    files = sorted(canonical_module(path) for path in
                   (ROOT / 't/qualification').glob('*-test.ss'))
    if not files:
        raise ValueError('no qualification modules discovered')
    shared = [path for path in files if path in PARALLEL_MODULES]
    exclusive = [path for path in files if path not in PARALLEL_MODULES]
    print(f'[test-suite] PLAN parallel={len(shared)} exclusive={len(exclusive)} '
          f'jobs={args.jobs}', flush=True)
    for path in exclusive:
        print(f'[test-suite] EXCLUSIVE {path}: '
              f'{EXCLUSIVE_REASONS.get(path, "module not yet reviewed for concurrency")}',
              flush=True)
    started = time.monotonic()
    results = execute_modules(shared, args.jobs, 'parallel')
    results += execute_modules(exclusive, 1, 'exclusive')
    completed = sorted(row['module'] for row in results)
    failed = completed != files or any(row['exit'] != 0 for row in results)
    receipt = ROOT / '.gerbil/test-execution' / f'suite-{time.time_ns()}.json'
    receipt.write_text(json.dumps(dict(
        configured_jobs=args.jobs, requested=files, failed=failed,
        seconds=time.monotonic()-started,
        results=sorted(results, key=lambda row: row['module'])), indent=2)+'\n')
    print(f'[test-suite] END modules={len(files)} failed={int(failed)} receipt={receipt}', flush=True)
    return int(failed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='action', required=True)
    single = commands.add_parser('run')
    single.add_argument('--module')
    single.add_argument('command', nargs=argparse.REMAINDER)
    many = commands.add_parser('parallel')
    many.add_argument('--jobs', default='auto')
    many.add_argument('files', nargs='*')
    all_tests = commands.add_parser('suite')
    all_tests.add_argument('--jobs', default='auto')
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, interrupted)
    try:
        if args.action in ('suite', 'parallel'):
            args.jobs = resolve_jobs(args.jobs)
        if args.action == 'suite':
            return suite(args)
        return run(args) if args.action == 'run' else parallel(args)
    except KeyboardInterrupt:
        return 130
    except (ValueError, TimeoutError, OSError, subprocess.SubprocessError) as error:
        print(f'[test-lane] FAIL {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
