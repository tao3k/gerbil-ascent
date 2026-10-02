#!/usr/bin/env python3
"""Process isolation for qualified tests; std/test still owns Case execution."""
import argparse
import concurrent.futures
import fcntl
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parent.parent
# Explicit admission: these fixtures compare values, not elapsed-time samples.
# Unknown modules, custom duration profiles, and performance recipes are exclusive.
PARALLEL_MODULES = frozenset({
    't/qualification/ascent-binary-program-test.ss',
    't/qualification/ascent-closure-candidates-test.ss',
    't/qualification/ascent-poo-primitives-test.ss',
    't/qualification/ascent-request-projection-test.ss',
    't/qualification/ascent-table-expression-test.ss',
    't/qualification/ascent-strata-test.ss',
    't/qualification/ascent-scc-summary-test.ss',
})



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
        return subprocess.call(command, cwd=ROOT, pass_fds=(descriptor,))
    # Never unlink this file: all callers must lock the same inode.
    with lock_path.open('a') as lock:
        acquire(lock, fcntl.LOCK_SH if shared else fcntl.LOCK_EX, lane)
        print(f'[test-lane] START {lane} {args.module or command[0]}', flush=True)
        environment = os.environ.copy()
        if not shared:
            environment['ASCENT_TEST_EXCLUSIVE_FD'] = str(lock.fileno())
        child = subprocess.Popen(command, cwd=ROOT, start_new_session=True,
                                 env=environment, pass_fds=(lock.fileno(),))
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
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGTERM)
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()


def parallel(args):
    files = [canonical_module(value) for value in (args.files or sorted(PARALLEL_MODULES))]
    if len(set(files)) != len(files) or any(value not in PARALLEL_MODULES for value in files):
        raise ValueError('parallel requires unique, explicitly admitted semantic modules')
    if args.jobs < 1:
        raise ValueError('jobs must be a positive integer')
    receipts = ROOT / '.gerbil/test-execution' / f'parallel-{time.time_ns()}'
    receipts.mkdir(parents=True)

    children = set()
    children_gate = threading.Lock()
    cancelled = threading.Event()

    def execute(path):
        log = receipts / (Path(path).stem + '.log')
        with log.open('w') as output:
            child = subprocess.Popen(['just', 'test-file', path], cwd=ROOT,
                                     stdout=output, stderr=subprocess.STDOUT,
                                     start_new_session=True)
            with children_gate:
                children.add(child)
                if cancelled.is_set():
                    os.killpg(child.pid, signal.SIGTERM)
            try:
                status = child.wait()
            finally:
                with children_gate:
                    children.discard(child)
        print(f'[parallel-test] END {path} exit={status} log={log}', flush=True)
        return status

    workers = min(args.jobs, len(files))
    print(f'[parallel-test] PLAN configured-jobs={args.jobs} workers={workers} modules={len(files)}', flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        pending = {pool.submit(execute, path) for path in files}
        failed = False
        try:
            while pending:
                done, pending = concurrent.futures.wait(
                    pending, timeout=5, return_when=concurrent.futures.FIRST_COMPLETED)
                for future in done:
                    failed |= future.result() != 0
                if pending:
                    print(f'[parallel-test] RUNNING remaining={len(pending)} logs={receipts}', flush=True)
        except BaseException:
            for future in pending:
                future.cancel()
            with children_gate:
                cancelled.set()
                for child in children:
                    if child.poll() is None:
                        os.killpg(child.pid, signal.SIGTERM)
            raise
    return int(failed)



def suite(args):
    files = sorted(canonical_module(path) for path in
                   (ROOT / 't/qualification').glob('*-test.ss'))
    if not files:
        raise ValueError('no qualification modules discovered')
    shared = [path for path in files if path in PARALLEL_MODULES]
    exclusive = [path for path in files if path not in PARALLEL_MODULES]
    print(f'[test-suite] PLAN parallel={len(shared)} exclusive={len(exclusive)} '
          f'jobs={args.jobs}', flush=True)
    failed = bool(parallel(argparse.Namespace(files=shared, jobs=args.jobs))) if shared else False
    receipts = ROOT / '.gerbil/test-execution' / f'exclusive-{time.time_ns()}'
    receipts.mkdir(parents=True)
    for path in exclusive:
        log = receipts / (Path(path).stem + '.log')
        with log.open('w') as output:
            child = subprocess.Popen(['just', 'test-file', path], cwd=ROOT,
                                     stdout=output, stderr=subprocess.STDOUT,
                                     start_new_session=True)
            try:
                while True:
                    try:
                        status = child.wait(timeout=5)
                        break
                    except subprocess.TimeoutExpired:
                        print(f'[test-suite] RUNNING exclusive {path} log={log}', flush=True)
            finally:
                if child.poll() is None:
                    os.killpg(child.pid, signal.SIGTERM)
                    try:
                        child.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(child.pid, signal.SIGKILL)
                        child.wait()
        failed |= status != 0
        print(f'[test-suite] END {path} exit={status} log={log}', flush=True)
    print(f'[test-suite] END modules={len(files)} failed={int(failed)}', flush=True)
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
