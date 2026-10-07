#!/usr/bin/env python3
"""Fail a qualification command that stops producing real output."""

import argparse
import os
import selectors
import signal
import subprocess
import sys
import time


def group_cpu(group: int) -> dict[int, float]:
    """Read real CPU time of the supervised process group, without commands."""
    listing = subprocess.check_output(
        ["ps", "-axo", "pid=,pgid=,time="], text=True, timeout=5
    )
    result = {}
    for line in listing.splitlines():
        pid, pgid, elapsed = line.split()
        if int(pgid) != group:
            continue
        days, separator, elapsed_time = elapsed.rpartition("-")
        parts = [float(part) for part in elapsed_time.split(":")]
        seconds = 0.0
        for part in parts:
            seconds = seconds * 60 + part
        result[int(pid)] = seconds + (int(days) * 86400 if separator else 0)
    return result


def stop_group(child: subprocess.Popen[bytes]) -> None:
    if child.poll() is not None:
        return
    try:
        os.killpg(child.pid, signal.SIGTERM)
        child.wait(timeout=1)
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGKILL)
        child.wait()
    except ProcessLookupError:
        pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--idle-seconds", type=float, default=5)
    parser.add_argument("--startup-seconds", type=float, default=5)
    parser.add_argument("--separate-stderr", action="store_true",
                        help="preserve stdout row protocols while supervising both streams")
    parser.add_argument("--cpu-progress", action="store_true",
                        help="build only: count measured process-group CPU advances as activity")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or args.idle_seconds <= 0 or args.startup_seconds <= 0:
        parser.error("expected a command and positive startup/idle limits")

    child = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE if args.separate_stderr else subprocess.STDOUT,
        start_new_session=True,
        bufsize=0,
    )
    assert child.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(child.stdout, selectors.EVENT_READ, sys.stdout.buffer)
    if child.stderr is not None:
        selector.register(child.stderr, selectors.EVENT_READ, sys.stderr.buffer)
    last_output = time.monotonic()
    saw_output = False
    cpu = {}
    last_cpu_sample = 0.0
    signal.signal(signal.SIGTERM, lambda _signum, _frame: sys.exit(124))
    try:
        while selector.get_map():
            ready = selector.select(timeout=0.25)
            if args.cpu_progress and time.monotonic() - last_cpu_sample >= 1:
                current_cpu = group_cpu(child.pid)
                advance = sum(max(0, value - cpu.get(pid, 0))
                              for pid, value in current_cpu.items())
                cpu = current_cpu
                last_cpu_sample = time.monotonic()
                if advance > 0:
                    last_output = last_cpu_sample
                    saw_output = True
                    print(f"[build-activity] cpu-advance={advance:.3f}s "
                          f"processes={len(cpu)}", file=sys.stderr, flush=True)
            if ready:
                for key, _events in ready:
                    chunk = os.read(key.fd, 65536)
                    if chunk:
                        key.data.write(chunk)
                        key.data.flush()
                        last_output = time.monotonic()
                        saw_output = True
                    else:
                        selector.unregister(key.fileobj)
            elif child.poll() is None and time.monotonic() - last_output > (
                args.idle_seconds if saw_output else args.startup_seconds
            ):
                limit = args.idle_seconds if saw_output else args.startup_seconds
                print(
                    f"[progress-watchdog] FAIL: no command "
                    f"{'output or CPU advance' if args.cpu_progress else 'output'} for "
                    f"{limit:g}s",
                    file=sys.stderr,
                    flush=True,
                )
                stop_group(child)
                return 124
        return child.wait()
    finally:
        stop_group(child)
        selector.close()
        child.stdout.close()
        if child.stderr is not None:
            child.stderr.close()


if __name__ == "__main__":
    raise SystemExit(main())
