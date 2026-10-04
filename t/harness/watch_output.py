#!/usr/bin/env python3
"""Fail a qualification command that stops producing real output."""

import argparse
import os
import selectors
import signal
import subprocess
import sys
import time


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
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or args.idle_seconds <= 0 or args.startup_seconds <= 0:
        parser.error("expected a command and positive startup/idle limits")

    child = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
        bufsize=0,
    )
    assert child.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(child.stdout, selectors.EVENT_READ)
    last_output = time.monotonic()
    saw_output = False
    signal.signal(signal.SIGTERM, lambda _signum, _frame: sys.exit(124))
    try:
        while selector.get_map():
            ready = selector.select(timeout=0.25)
            if ready:
                chunk = os.read(child.stdout.fileno(), 65536)
                if chunk:
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.buffer.flush()
                    last_output = time.monotonic()
                    saw_output = True
                else:
                    selector.unregister(child.stdout)
            elif child.poll() is None and time.monotonic() - last_output > (
                args.idle_seconds if saw_output else args.startup_seconds
            ):
                limit = args.idle_seconds if saw_output else args.startup_seconds
                print(
                    f"[progress-watchdog] FAIL: no command output for "
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


if __name__ == "__main__":
    raise SystemExit(main())
