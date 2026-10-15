# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Run independent native consumers with a fresh process per test file."""
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time
import threading
import uuid

from .formal import capacity
from .supervision import forward_output, stop_group

ROOT = Path.cwd().resolve()
API_FILES = (
    "test_binding_modes.py", "test_computational_evidence.py", "test_datalog.py",
    "test_review.py", "test_rule_source.py", "test_rule_sources.py", "test_uf_weighted.py",
)


def inventory(directory: Path) -> list[tuple[str, Path]]:
    files = sorted(directory.glob("test_*.py"))
    if not files or any(not (directory / name).is_file() for name in API_FILES):
        raise ValueError("incomplete native consumer inventory")
    return [("pyo3", path) for path in files]


def compiled_inputs():
    from ascent.build import runtime_identity
    return runtime_identity()


def qualification_inputs(files: list[Path]) -> dict[str, str]:
    """Bind actual installed PyO3 bytes, build-frozen inputs and runtime syntax resources."""
    receipt=compiled_inputs()
    if receipt['schema']!='ascent.rust-build.v1': raise ValueError('compiled Rust identity required')
    expected={str(ROOT/name):sha for name,sha in receipt['sourceInputs'].items()}
    expected.update(receipt['runtimeInputs'])
    extension=importlib.util.find_spec('ascent._core')
    if extension is None or not extension.origin: raise ValueError('installed PyO3 extension required')
    paths=[*files,Path(extension.origin),ROOT/'justfile',ROOT/'.github/workflows/ci.yml']
    paths.extend((ROOT/'workbench/src/ascent_workbench').glob('*.py'))
    paths.extend((ROOT/'python/src/ascent').glob('*.py'))
    for path in paths:
        expected[str(path.resolve())]=hashlib.sha256(path.read_bytes()).hexdigest()
    for name,sha in expected.items():
        if not Path(name).is_file() or hashlib.sha256(Path(name).read_bytes()).hexdigest()!=sha:
            raise ValueError('qualification input drift: '+name)
    return expected


def main() -> int:
    started = time.monotonic()
    deadline = started + 120  # The original whole-matrix deadline.
    directory = ROOT / "workbench/engine_tests"
    tasks = inventory(directory)
    files = [path for _, path in tasks]
    output = ROOT / ".cache/ascent/native-consumers" / uuid.uuid4().hex
    output.mkdir(parents=True)
    inputs = qualification_inputs(files)
    forward_output(sys.stdout.buffer, f"NATIVE-INPUTS-OK files={len(inputs)}\n".encode(),
                   min(5, deadline - time.monotonic()))
    cancelled = threading.Event()
    previous_term = signal.signal(signal.SIGTERM, lambda _signum, _frame: cancelled.set())
    output_lock = threading.Lock()
    last_output = [time.monotonic()]

    def execute(backend: str, path: Path) -> tuple[str, int]:
        label = f"{backend}-{path.stem}"
        if cancelled.is_set() or time.monotonic() >= deadline:
            raise TimeoutError(f"{label}: matrix cancelled or deadline exceeded before launch")
        with (output / f"{label}.out").open("wb") as log:
            # Native runtime shutdown is terminal. Threads only coordinate
            # independent processes; no VM is reused across files or backends.
            child = subprocess.Popen([sys.executable, "-u", "-m", "unittest", "discover",
                "-s", str(directory), "-p", path.name, "-v"],
                cwd=ROOT, env=os.environ.copy(),
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
            selector = selectors.DefaultSelector()
            selector.register(child.stdout, selectors.EVENT_READ)
            try:
                while selector.get_map():
                    # The original supervisor observes the entire matrix's
                    # actual output, including concurrent consumers.
                    if cancelled.is_set() or time.monotonic() >= deadline or time.monotonic() - last_output[0] > 5:
                        raise TimeoutError(f"{label}: original deadline or real-output watchdog exceeded")
                    for key, _ in selector.select(timeout=0.25):
                        chunk = os.read(key.fd, 65536)
                        if chunk:
                            log.write(chunk)
                            log.flush()
                            with output_lock:
                                forward_output(sys.stdout.buffer, chunk, min(5, deadline - time.monotonic()))
                                last_output[0] = time.monotonic()
                        else:
                            selector.unregister(key.fileobj)
                code = child.wait(timeout=max(0, deadline - time.monotonic()))
            finally:
                stop_group(child)
                selector.close()
                child.stdout.close()
        with output_lock:
            forward_output(sys.stdout.buffer, f"NATIVE-CONSUMER {label} exit={code}\n".encode(),
                           min(5, deadline - time.monotonic()))
        return label, code

    outcomes = {}
    error = None
    try:
        with ThreadPoolExecutor(max_workers=min(capacity(heap_mib=3072), len(tasks))) as pool:
            futures = [pool.submit(execute, backend, path) for backend, path in tasks]
            try:
                for future in as_completed(futures):
                    label, code = future.result()
                    outcomes[label] = code
            finally:
                cancelled.set()
                for future in futures:
                    future.cancel()
    except Exception as failure:
        error = str(failure)
        print(error, file=sys.stderr)
    finally:
        signal.signal(signal.SIGTERM, previous_term)
    changed = [name for name, sha in inputs.items()
               if not Path(name).is_file() or hashlib.sha256(Path(name).read_bytes()).hexdigest() != sha]
    passed = (len(outcomes) == len(tasks) and not any(outcomes.values()) and not changed
              and error is None and time.monotonic() <= deadline)
    (output / "receipt.json").write_text(json.dumps({"schema": "ascent.pyo3-consumers.v1", "expectedGroups": len(tasks), "outcomes": outcomes,
        "seconds": time.monotonic() - started, "budgetSeconds": 120, "inputs": inputs,
        "changedInputs": changed, "error": error, "passed": passed}, indent=2) + "\n")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
