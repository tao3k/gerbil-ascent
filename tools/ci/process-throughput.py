#!/usr/bin/env python3
"""Orchestrate real Rust-owned production sessions; never implement inference here."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import signal
import subprocess
import threading
import time

COMPILERS = {"cargo", "rustc", "gxi", "gsc", "cc1", "cc1plus", "clang", "clang++", "gcc", "gcc-16", "lean", "lake"}


def compilers():
    result = subprocess.run(["ps", "-A", "-o", "pid=,comm="], check=True, text=True, capture_output=True)
    return [{"pid": int(pid), "command": command} for line in result.stdout.splitlines()
            for pid, command in [line.strip().split(None, 1)] if Path(command).name in COMPILERS]


def fields(line):
    return dict(field.split("=", 1) for field in line.split()[1:])


def request_phases(stdout, tasks, samples):
    """Admit exact, unique fixed-work observations before reporting phase costs."""
    lines = stdout.splitlines()
    expected = "sample\ttask\tlatency_ns\tcompletion_ns\treplace_ns\trun_export_ns\tanswer_sha"
    if not lines or lines[0] != expected:
        raise ValueError("missing production request observations")
    observed = {}
    for line in lines[1:]:
        sample, task, latency, completion, replace, run_export, answer = line.split("\t")
        sample, task, latency, completion, replace, run_export = map(
            int, (sample, task, latency, completion, replace, run_export))
        key = sample, task
        if (key in observed or not 0 <= sample < samples
                or not sample * tasks <= task < (sample + 1) * tasks
                or min(latency, completion, replace, run_export) < 0
                or replace + run_export > latency or len(answer) != 64
                or any(c not in "0123456789abcdef" for c in answer)):
            raise ValueError("invalid or duplicate production request observation")
        observed[key] = replace, run_export
    if len(observed) != tasks * samples:
        raise ValueError("incomplete production request observations")
    return {"median_replace_ms": statistics.median(v[0] / 1e6 for v in observed.values()),
            "median_run_export_ms": statistics.median(v[1] / 1e6 for v in observed.values()),
            "checked_fixed_work_requests": len(observed)}


def run_case(args, case, configuration, work_distribution):
    """Run one original fixed-work row with exactly the shared admission rules."""
    name, tasks, groups, width = case
    mode, owners, threads = configuration
    key = f"{name}-{mode}-vm{owners}-threads{threads}"
    command = [str(args.benchmark.resolve()), str(args.worker.resolve()), mode, str(owners), str(threads), str(tasks), str(groups), str(width), "5", "30"]
    audit, errors, stop = [], [], threading.Event()
    def sample():
        while not stop.is_set():
            try:
                found = compilers()
                if found:
                    audit.append({"monotonic": time.monotonic(), "processes": found})
            except Exception as error:
                errors.append(str(error))
            stop.wait(0.5)
    observer = threading.Thread(target=sample)
    observer.start()
    started = time.monotonic()
    process = subprocess.Popen(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=240)
        status = process.returncode
    except subprocess.TimeoutExpired:
        status = "timeout"
        os.killpg(process.pid, signal.SIGTERM)
        try:
            stdout, stderr = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate(timeout=5)
    finally:
        stop.set()
        observer.join()
    (args.output / f"{key}.stdout").write_text(stdout)
    (args.output / f"{key}.stderr").write_text(stderr)
    samples = [fields(line) for line in stderr.splitlines() if line.startswith("PROCESS-SAMPLE ")]
    identities = [fields(line) for line in stderr.splitlines() if line.startswith("PROCESS-OWNER ")]
    soaks = [fields(line) for line in stderr.splitlines() if line.startswith("PROCESS-SOAK ")]
    ready = [fields(line) for line in stderr.splitlines() if line.startswith("PROCESS-READY ")]
    soak_valid = (len(soaks) == 1 and soaks[0]["mode"] == mode
                  and soaks[0]["vms"] == str(owners)
                  and soaks[0]["rust_threads"] == str(threads)
                  and soaks[0]["clients"] == "12"
                  and int(soaks[0]["requested_ns"]) == 30_000_000_000
                  and int(soaks[0]["wall_ns"]) >= 30_000_000_000
                  and int(soaks[0]["completed_requests"]) > 0
                  and int(soaks[0]["minimum_client_requests"]) > 0
                  and soaks[0]["completed_requests"] == soaks[0]["checked_requests"]
                  and int(soaks[0]["histogram_resolution_ns"]) == 100_000
                  and int(soaks[0]["histogram_buckets"]) == 65_536
                  and 0 <= int(soaks[0]["p50_lower_ns"]) <= int(soaks[0]["p50_upper_ns"])
                  and 0 <= int(soaks[0]["p95_lower_ns"]) <= int(soaks[0]["p95_upper_ns"]))
    transport = ready[0].get("checkpoint_transport") if len(ready) == 1 else None
    try:
        checkpoint_valid = transport in ("buffered-socket", "shared-futex", "shared-darwin-wait")
        for observation in [*samples, *soaks]:
            total = int(observation.get("checkpoints", -1))
            shared = int(observation.get("shared_checkpoints", -1))
            checkpoint_valid = checkpoint_valid and 0 <= shared <= total
            if mode == "rayon":
                checkpoint_valid = checkpoint_valid and total == 0 and int(observation["native_calls"]) == 0
            elif transport == "buffered-socket":
                checkpoint_valid = checkpoint_valid and shared == 0
            else:
                checkpoint_valid = checkpoint_valid and shared > 0
    except (ValueError, TypeError, KeyError) as error:
        checkpoint_valid = False
        errors.append(f"invalid checkpoint observations: {error}")
    try:
        phases = request_phases(stdout, tasks, 5)
    except (ValueError, TypeError) as error:
        phases = {}
        errors.append(str(error))
    valid = (status == 0 and soak_valid and checkpoint_valid and len(samples) == 5
             and len(ready) == 1 and ready[0].get("work_distribution") == work_distribution
             and {value["sample"] for value in samples} == {str(i) for i in range(5)}
             and all(value["mode"] == mode and value["vms"] == str(owners)
                     and value["rust_threads"] == str(threads) and value["tasks"] == str(tasks)
                     and value["clients"] == "12" for value in samples)
             and "ASCENT-PROCESS-FORCED-STOP" not in stderr
             and "ASCENT-PROCESS-SHUTDOWN-ERROR" not in stderr
             and "ASCENT-CHECKPOINT-TRANSPORT-ERROR" not in stderr and len(identities) == owners
             and len({value["pid"] for value in identities}) == owners
             and all(value["processors"] == "1" for value in identities) and not audit and not errors)
    row = {"key": key, "workload": name, "mode": mode, "vms": owners, "rust_threads": threads,
           "tasks": tasks, "groups": groups, "width": width,
           "input_edges_per_request": groups * (width - 1),
           "expected_rows_per_request": groups * width * (width - 1) // 2,
           "checkpoint_transport": transport,
           "request_phases": phases, "command": command, "status": status,
           "process_wall_seconds": time.monotonic()-started, "samples": samples, "soak": soaks, "owners": identities,
           "foreign_compilers": audit, "audit_errors": errors, "valid": valid}
    if valid:
        row["median_throughput_per_second"] = statistics.median(float(value["throughput_per_s"]) for value in samples)
        row["median_p50_request_ms"] = statistics.median(int(value["p50_ns"])/1e6 for value in samples)
        row["median_p95_request_ms"] = statistics.median(int(value["p95_ns"])/1e6 for value in samples)
        row["maximum_overlapping_vm_calls"] = max(int(value["max_overlapping_vm_calls"]) for value in samples)
    print(key, status, "VALID" if valid else "REJECTED", flush=True)
    return row


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--benchmark", type=Path, required=True)
    parser.add_argument("--worker", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-cpus", type=int)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    receipt = {"schema": "ascent.production-process-throughput.v3", "host": platform.platform(),
               "logical_cpus": os.cpu_count(), "source_head": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
               "harness_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
               "benchmark_sha256": hashlib.sha256(args.benchmark.read_bytes()).hexdigest(),
               "worker_sha256": hashlib.sha256(args.worker.read_bytes()).hexdigest(),
               "cargo_lock_sha256": hashlib.sha256(Path("rust/Cargo.lock").read_bytes()).hexdigest(),
               "scheme_bridge": sorted({line.strip() for line in Path("rust/Cargo.lock").read_text().splitlines()
                                         if line.startswith('source = "git+https://github.com/tao3k/gerbil-scheme-rust?')}),
               "work_distribution": os.environ.get("ASCENT_WORK_DISTRIBUTION", "adaptive"),
               "runs": []}
    if args.expected_cpus is not None and os.cpu_count() != args.expected_cpus:
        raise SystemExit(f"expected {args.expected_cpus} CPUs, observed {os.cpu_count()}; no measurements admitted")
    source_paths = ["rust", "interface", "program", "core", "table", "bindings", "tools/ci/process-throughput.py"]
    tracked_clean = subprocess.run(["git", "diff", "--quiet", "HEAD", "--", *source_paths]).returncode == 0
    untracked = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard", "--", *source_paths], text=True).splitlines()
    receipt["source_clean"] = tracked_clean and not untracked
    if not receipt["source_clean"]:
        raise SystemExit("runtime sources differ from the recorded head; no measurements admitted")
    cases = [("small", 240, 4, 8), ("closure", 120, 16, 12),
             ("parallel-closure", 24, 256, 16)]
    modes = [("vm", 1, 1), ("vm", 3, 1), ("vm", 12, 1)] + [("rayon", 1, threads) for threads in (1, 3, 6, 8, 12)]
    for case in cases:
        for configuration in modes:
            receipt["runs"].append(run_case(args, case, configuration, receipt["work_distribution"]))
            (args.output/"result.json").write_text(json.dumps(receipt, indent=2)+"\n")
    for name, *_ in cases:
        rows = [row for row in receipt["runs"] if row["workload"] == name]
        hashes = [{sample["sample"]: sample["answer_sha"] for sample in row["samples"]} for row in rows]
        matched = bool(hashes and all(value == hashes[0] for value in hashes) and len(hashes[0]) == 5)
        baseline = next(row for row in rows if row["mode"] == "vm" and row["vms"] == 1)
        rayon_baseline = next(row for row in rows if row["mode"] == "rayon" and row["rust_threads"] == 1)
        for row in rows:
            row["matched_complete_answers"] = matched
            if matched and row["valid"] and baseline["valid"]:
                row["throughput_speedup_vs_one_vm"] = row["median_throughput_per_second"]/baseline["median_throughput_per_second"]
            if matched and row["valid"] and row["mode"] == "rayon" and rayon_baseline["valid"]:
                row["throughput_speedup_vs_one_rayon_thread"] = row["median_throughput_per_second"]/rayon_baseline["median_throughput_per_second"]
    receipt["complete"] = all(row["valid"] and row["matched_complete_answers"] for row in receipt["runs"])
    (args.output/"result.json").write_text(json.dumps(receipt, indent=2)+"\n")
    if not receipt["complete"]:
        raise SystemExit("incomplete or contaminated production throughput matrix; failures retained")


if __name__ == "__main__":
    main()
