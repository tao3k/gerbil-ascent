#!/usr/bin/env python3
"""Orchestrate real Rust-owned production sessions; never implement inference here."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import statistics
import signal
import subprocess
import sys
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "workbench/src"))
from ascent_workbench.supervision import signal_group

COMPILERS = {"cargo", "rustc", "gxi", "gsc", "cc1", "cc1plus", "clang", "clang++", "gcc", "gcc-16", "lean", "lake"}


def process_snapshot():
    result = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,rss=,comm="],
                            check=True, text=True, capture_output=True)
    return [{"pid": int(pid), "ppid": int(ppid), "rss_kib": int(rss), "command": command}
            for line in result.stdout.splitlines()
            for pid, ppid, rss, command in [line.strip().split(None, 3)]]


def compilers(snapshot=None):
    return [{"pid": row["pid"], "command": row["command"]}
            for row in (process_snapshot() if snapshot is None else snapshot)
            if Path(row["command"]).name in COMPILERS]


def process_tree_resources(snapshot, root):
    """Resident sums include shared pages; this is not physical memory ownership."""
    population = {root}
    while True:
        expanded = population | {row["pid"] for row in snapshot if row["ppid"] in population}
        if expanded == population:
            break
        population = expanded
    rows = [row for row in snapshot if row["pid"] in population]
    return {"pids": sorted(row["pid"] for row in rows),
            "processes": len(rows), "rss_sum_kib": sum(row["rss_kib"] for row in rows),
            "maximum_process_rss_kib": max((row["rss_kib"] for row in rows), default=0)}


def parse_thread_counts(output, pids, darwin):
    rows = output.splitlines()
    result = {}
    if darwin:
        if not rows or "PID" not in rows[0]:
            return result
        end = rows[0].index("PID") + len("PID")
        rows = [row[:end].split()[-1] for row in rows[1:] if row[:end].split()]
    for row in rows:
        value = row.strip()
        if value.isdecimal() and int(value) in pids:
            pid = int(value)
            result[pid] = result.get(pid, 0) + 1
    return result


def thread_population(pids):
    if not pids:
        return {}
    darwin = platform.system() == "Darwin"
    command = ["ps", "-M" if darwin else "-L", "-p", ",".join(map(str, pids))]
    if not darwin:
        command += ["-o", "pid="]
    snapshot = subprocess.run(command, text=True, capture_output=True, check=False)
    if snapshot.returncode not in (0, 1):
        raise ValueError("thread observer failed: " + snapshot.stderr.strip())
    return parse_thread_counts(snapshot.stdout, set(pids), darwin)


def cpu_resources(path):
    """Read OS wait accounting for the benchmark and its reaped descendants."""
    raw = path.read_text()
    header = re.search(r"([0-9.]+) real\s+([0-9.]+) user\s+([0-9.]+) sys", raw)
    resident = re.search(r"(\d+)\s+maximum resident set size", raw)
    if header is None or resident is None:
        raise ValueError("missing OS CPU or maximum resident accounting")
    wall, user, system = map(float, header.groups())
    return {"wall_seconds": wall, "user_seconds": user, "system_seconds": system,
            "average_cpu_cores": (user + system) / wall if wall > 0 else 0,
            "maximum_process_rss_bytes": int(resident[1]),
            "raw_receipt": str(path), "covers": "benchmark lifetime including startup and shutdown"}


def owner_identities_valid(identities, mode, owners):
    try:
        return (len(identities) == owners
                and len({int(value["domain"]) for value in identities}) == owners
                and all(int(value["domain"]) > 0 and value["processors"] == "1" for value in identities)
                and len({int(value["pid"]) for value in identities}) == (1 if mode == "instances" else owners))
    except (ValueError, KeyError, TypeError):
        return False


def owner_shutdown_valid(stderr, mode, owners):
    if mode != "instances":
        return True
    receipts = [fields(line) for line in stderr.splitlines() if line.startswith("OWNER-SHUTDOWN ")]
    return receipts == [dict(mode="instances", joined=str(owners), pending="0", panicked="0", roots="0")]


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


def longest_request(traces, soaks, first_task=0):
    """Admit one request's partition, never independent per-phase maxima."""
    schema = soaks[0].get("slowest_schema") if len(soaks) == 1 else None
    if not traces and schema is None:
        return None  # Historical receipts did not capture this partition.
    if schema != "same-request-v1" or len(traces) != 1 or len(soaks) != 1:
        raise ValueError("missing or repeated same-request phase evidence")
    trace, soak = traces[0], soaks[0]
    if any(trace[k] != soak[k] for k in ("mode", "vms", "rust_threads", "clients")):
        raise ValueError("foreign same-request phase evidence")
    values = {k: int(trace[k]) for k in
              ("task", "total_ns", "replace_ns", "run_export_ns", "validation_ns")}
    if (min(values.values()) < 0
            or not first_task <= values["task"] < first_task + int(soak["completed_requests"])
            or values["total_ns"] != int(soak["max_ns"])
            or sum(values[k] for k in ("replace_ns", "run_export_ns", "validation_ns"))
            != values["total_ns"]):
        raise ValueError("invalid same-request phase partition")
    return values


def run_case(args, case, configuration, work_distribution, diagnostic=False):
    """Run one original fixed-work row with exactly the shared admission rules."""
    name, tasks, groups, width = case
    mode, owners, threads = configuration
    key = f"{name}-{mode}-vm{owners}-threads{threads}"
    command = [str(args.benchmark.resolve()), str(args.worker.resolve()), mode, str(owners), str(threads), str(tasks), str(groups), str(width), "5", "30"]
    resource_path = args.output / f"{key}.resources"
    if platform.system() == "Darwin":
        launch_command = ["/usr/bin/time", "-l", "-o", str(resource_path), *command]
    else:
        launch_command = ["/usr/bin/time", "-o", str(resource_path), "-f",
                          "%e real %U user %S sys\n%M maximum resident set size", *command]
    environment = dict(os.environ)
    if diagnostic:
        environment["ASCENT_PROCESS_TRACE"] = "1"
    traced = "ASCENT_PROCESS_TRACE" in environment
    audit, resources, errors, stop = [], [], [], threading.Event()
    process = None
    def observe():
        try:
            snapshot = process_snapshot()
            found = compilers(snapshot)
            if process is not None:
                population = process_tree_resources(snapshot, process.pid)
                threads = thread_population(population["pids"])
                resources.append({"monotonic": time.monotonic(), **population,
                                  "threads": sum(threads.values()), "thread_counts": threads})
            if found:
                audit.append({"monotonic": time.monotonic(), "processes": found})
        except Exception as error:
            errors.append(str(error))
    def sample():
        while not stop.wait(0.5):
            observe()
    observer = threading.Thread(target=sample)
    observe()
    started = time.monotonic()
    process = subprocess.Popen(launch_command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True, env=environment)
    observe()
    observer.start()
    try:
        stdout, stderr = process.communicate(timeout=240)
        status = process.returncode
    except subprocess.TimeoutExpired:
        status = "timeout"
        signal_group(process.pid, signal.SIGTERM)
        try:
            stdout, stderr = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            signal_group(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate(timeout=5)
    finally:
        stop.set()
        observer.join()
    (args.output / f"{key}.stdout").write_text(stdout)
    (args.output / f"{key}.stderr").write_text(stderr)
    samples = [fields(line) for line in stderr.splitlines() if line.startswith("PROCESS-SAMPLE ")]
    identities = [fields(line) for line in stderr.splitlines() if line.startswith("PROCESS-OWNER ")]
    soaks = [fields(line) for line in stderr.splitlines() if line.startswith("PROCESS-SOAK ")]
    slowest = [fields(line) for line in stderr.splitlines() if line.startswith("PROCESS-SLOWEST ")]
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
        checkpoint_valid = transport in ("buffered-socket", "shared-futex", "shared-darwin-wait", "shared-local-control", "direct-owner")
        checkpoint_valid = checkpoint_valid and ((mode == "instances") == (transport == "direct-owner"))
        for observation in [*samples, *soaks]:
            total = int(observation.get("checkpoints", -1))
            shared = int(observation.get("shared_checkpoints", -1))
            checkpoint_valid = checkpoint_valid and 0 <= shared <= total
            if mode == "rayon":
                checkpoint_valid = checkpoint_valid and total == 0 and int(observation["native_calls"]) == 0
            elif transport in ("buffered-socket", "direct-owner"):
                checkpoint_valid = checkpoint_valid and shared == 0 and total > 0
            else:
                checkpoint_valid = checkpoint_valid and shared > 0
    except (ValueError, TypeError, KeyError) as error:
        checkpoint_valid = False
        errors.append(f"invalid checkpoint observations: {error}")
    try:
        phases = request_phases(stdout, tasks, 5)
        longest = longest_request(slowest, soaks, 5 * tasks + 12)
    except (ValueError, TypeError, KeyError) as error:
        phases, longest = {}, None
        errors.append(str(error))
    if not any(row["threads"] > 0 for row in resources):
        errors.append("missing owned-process thread observations")
    valid = (not traced and status == 0 and soak_valid and checkpoint_valid and len(samples) == 5
             and len(ready) == 1 and ready[0].get("work_distribution") == work_distribution
             and {value["sample"] for value in samples} == {str(i) for i in range(5)}
             and all(value["mode"] == mode and value["vms"] == str(owners)
                     and value["rust_threads"] == str(threads) and value["tasks"] == str(tasks)
                     and value["clients"] == "12" for value in samples)
             and "ASCENT-PROCESS-FORCED-STOP" not in stderr
             and "ASCENT-PROCESS-SHUTDOWN-ERROR" not in stderr
             and "ASCENT-CHECKPOINT-TRANSPORT-ERROR" not in stderr
             and owner_identities_valid(identities, mode, owners)
             and owner_shutdown_valid(stderr, mode, owners) and not audit and not errors)
    try:
        cpu = cpu_resources(resource_path)
        if platform.system() != "Darwin":
            cpu["maximum_process_rss_bytes"] *= 1024
    except (OSError, ValueError) as error:
        cpu = {"error": str(error)}
        errors.append(str(error))
        valid = False
    row = {"key": key, "workload": name, "mode": mode, "vms": owners, "rust_threads": threads,
           "tasks": tasks, "groups": groups, "width": width,
           "input_edges_per_request": groups * (width - 1),
           "expected_rows_per_request": groups * width * (width - 1) // 2,
           "checkpoint_transport": transport,
           "request_phases": phases, "command": command, "status": status,
           "process_wall_seconds": time.monotonic()-started, "samples": samples, "soak": soaks, "slowest": slowest, "longest_request": longest, "owners": identities,
           "resources": {"cpu": cpu, "sampling_interval_seconds": 0.5,
                         "peak_threads": max((r["threads"] for r in resources), default=0),
                         "rss_sum_includes_shared_pages": True,
                         "peak_processes": max((r["processes"] for r in resources), default=0),
                         "peak_rss_sum_kib": max((r["rss_sum_kib"] for r in resources), default=0),
                         "maximum_process_rss_kib": max((r["maximum_process_rss_kib"] for r in resources), default=0),
                         "samples": resources},
           "foreign_compilers": audit, "audit_errors": errors, "diagnostic_only": traced, "valid": valid}
    if valid:
        row["median_throughput_per_second"] = statistics.median(float(value["throughput_per_s"]) for value in samples)
        row["median_p50_request_ms"] = statistics.median(int(value["p50_ns"])/1e6 for value in samples)
        row["median_p95_request_ms"] = statistics.median(int(value["p95_ns"])/1e6 for value in samples)
        row["maximum_overlapping_vm_calls"] = max(int(value["max_overlapping_vm_calls"]) for value in samples)
    print(key, status, "VALID" if valid else "REJECTED", flush=True)
    return row


def diagnose_failed_vm_cases(args, rows, work_distribution):
    """One instrumented reproduction after ALL original measurements; never admit it."""
    failed = [row for row in rows if row["mode"] == "vm" and not row["valid"]
              and row["status"] != 0 and not row.get("diagnostic_only", False)]
    if not failed:
        return
    root = args.output / "diagnostics"
    root.mkdir()
    receipt = {"schema": "ascent.failed-case-diagnostics.v1", "admitted": False, "runs": []}
    for original in failed:
        output = root / original["key"]
        output.mkdir()
        scoped = argparse.Namespace(output=output, benchmark=args.benchmark, worker=args.worker)
        try:
            observation = run_case(scoped,
                (original["workload"], original["tasks"], original["groups"], original["width"]),
                (original["mode"], original["vms"], original["rust_threads"]), work_distribution,
                diagnostic=True)
        except Exception as error:
            observation = {"key": original["key"], "diagnostic_error": str(error)}
        receipt["runs"].append({"original_status": original["status"], "observation": observation})
        (root / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")


def configurations(include_instances):
    # The Rust coordinator is shared across all twelve callers. VM processor
    # receipts remain one; these are separate from idle Rust pool workers.
    modes = [("vm", owners, 12) for owners in (1, 3, 12)]
    if include_instances:
        modes += [("instances", owners, 12) for owners in (1, 3, 12)]
    return modes + [("rayon", 1, threads) for threads in (1, 3, 6, 8, 12)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--benchmark", type=Path, required=True)
    parser.add_argument("--worker", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-cpus", type=int)
    parser.add_argument("--include-instances", action="store_true",
                        help="compare macOS independent single-thread VMs in one process")
    args = parser.parse_args()
    if args.include_instances and platform.system() != "Darwin":
        raise SystemExit("the upstream instance image path is macOS-only")
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
    modes = configurations(args.include_instances)
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
        diagnose_failed_vm_cases(args, receipt["runs"], receipt["work_distribution"])
        raise SystemExit("incomplete or contaminated production throughput matrix; failures retained")


if __name__ == "__main__":
    main()
