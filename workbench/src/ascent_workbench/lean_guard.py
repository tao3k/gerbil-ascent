# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Thin ASCENT adapter to the process Guard in the locked LeanPoo dependency."""
from functools import cache
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[3]
PROJECT = ROOT / "packages/proofs/lean"


@cache
def process_guard():
    """Import the exact committed Guard used by the declared Lean dependency."""
    manifest = json.loads((PROJECT / "lake-manifest.json").read_text())
    package = next(item for item in manifest["packages"] if item["name"] == "LeanPoo")
    dependency = PROJECT / ".lake/packages/LeanPoo"
    source = dependency / "tools/process_guard.py"
    if not source.is_file():
        raise RuntimeError("locked LeanPoo Guard is unavailable; restore declared Lake dependencies")
    committed = subprocess.check_output(
        ["git", "-C", str(dependency), "show", package["rev"] + ":tools/process_guard.py"], timeout=5)
    if source.read_bytes() != committed:
        raise RuntimeError("LeanPoo process Guard differs from its locked source")
    spec = importlib.util.spec_from_file_location("_ascent_lean_poo_process_guard", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module, package["rev"], hashlib.sha256(committed).hexdigest()


def run_checked(command, seconds, on_line, *, cwd=PROJECT, stderr=subprocess.STDOUT):
    """Use upstream collection/cleanup; report actual status, CPU, RSS and leaks."""
    guard, revision, digest = process_guard()
    before = {thread.ident for thread in threading.enumerate()}
    started = time.monotonic()
    process = subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE, stderr=stderr,
                               start_new_session=True)
    code, usage = guard.collect(process, on_line, seconds)
    added = {thread.ident for thread in threading.enumerate()} - before
    if added:
        raise RuntimeError(f"Lean Guard retained helper threads: {sorted(added)}")
    return code, {
        "schema": "ascent.lean-poo-guard.v1", "guard_revision": revision,
        "guard_sha256": digest, "command": command, "returncode": code,
        "wall_seconds": time.monotonic() - started,
        "cpu_seconds": usage.ru_utime + usage.ru_stime,
        "max_rss_bytes": usage.ru_maxrss * (1 if sys.platform == "darwin" else 1024),
        "additional_helper_threads": len(added), "direct_child_reaped": process.returncode is not None,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("file", "build", "render"))
    parser.add_argument("arguments", nargs="*")
    args = parser.parse_args()
    if args.mode == "build":
        if args.arguments:
            parser.error("build accepts no additional arguments")
        command, seconds = ["lake", "-v", "build", "AscentProof", "AscentProofTests"], 180
    else:
        batch = (args.mode == "render" and len(args.arguments) > 2
                 and args.arguments[:2] == ["ExecutionPolicy.lean", "batch"])
        if not batch and len(args.arguments) != (1 if args.mode == "file" else 2):
            parser.error("expected a Lean source file and, for render, a language")
        source = args.arguments[0]
        if not source.endswith(".lean") or not (PROJECT / source).is_file():
            parser.error("expected an existing Lean source file")
        command = ["lake", "env", "lean", "-j2", "-M1024", "-T10000000"]
        command += [source] if args.mode == "file" else ["--run", *args.arguments]
        seconds = 30
    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, lambda number, _frame: sys.exit(128 + number))
    try:
        def emit(line):
            sys.stdout.buffer.write(line)
            sys.stdout.buffer.flush()
        code, receipt = run_checked(command, seconds, emit, stderr=None)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"LEAN-GUARD-FAIL {error}", file=sys.stderr)
        return 1
    print("LEAN-GUARD-RECEIPT " + json.dumps(receipt, sort_keys=True), file=sys.stderr)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
