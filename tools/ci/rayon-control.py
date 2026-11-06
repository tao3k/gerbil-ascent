#!/usr/bin/env python3
"""Explicit same-host phase experiment; the Rust benchmark owns all inference."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
from types import SimpleNamespace

SPEC = importlib.util.spec_from_file_location(
    "process_throughput", Path(__file__).with_name("process-throughput.py"))
MATRIX = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MATRIX)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def artifacts(path):
    result = {}
    for line in path.read_text().splitlines():
        value = json.loads(line)
        name = value.get("target", {}).get("name")
        executable = value.get("executable")
        if value.get("reason") == "compiler-artifact" and executable and name in {
                "process_throughput", "ascent-scheme-worker"}:
            if name in result:
                raise ValueError("duplicate executable in one build graph")
            result[name] = Path(executable).resolve(strict=True)
    if set(result) != {"process_throughput", "ascent-scheme-worker"}:
        raise ValueError("incomplete benchmark/worker build graph")
    return result


def head(root):
    return subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()


VM_INPUT_PATHS = ("rust/Cargo.toml", "rust/Cargo.lock", "*.ss", "bindings/c",
                  "gerbil.pkg", "dev/gerbil.pkg", "rust/ascent-scheme",
                  ":(exclude)program/rust-execution.ss")


def verify_vm_inputs(reference, candidate, root):
    # The build-only Rust kernel producer is part of the compared implementation.
    subprocess.run(["git", "-C", str(root), "diff", "--exit-code", reference,
                    candidate, "--", *VM_INPUT_PATHS], check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference-source", type=Path, required=True)
    parser.add_argument("--reference-build", type=Path, required=True)
    parser.add_argument("--candidate-build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-cpus", type=int, required=True)
    args = parser.parse_args()
    if os.cpu_count() != args.expected_cpus:
        raise SystemExit("unexpected CPU population; no measurement admitted")
    roots = {"reference": args.reference_source.resolve(strict=True), "candidate": Path.cwd()}
    source_heads = {label: head(root) for label, root in roots.items()}
    source_paths = ["rust", "interface", "program", "core", "table", "bindings", "tools/ci"]
    for root in roots.values():
        subprocess.run(["git", "-C", str(root), "diff", "--exit-code", "HEAD", "--", *source_paths], check=True)
        untracked = subprocess.check_output(["git", "-C", str(root), "ls-files", "--others",
                                            "--exclude-standard", "--", *source_paths], text=True)
        if untracked.strip():
            raise SystemExit("untracked runtime inputs; no measurement admitted")
    # One dependency graph and VM frontend cohort; compare Rust kernel generation.
    verify_vm_inputs(source_heads["reference"], source_heads["candidate"], roots["candidate"])
    pairs = {"reference": artifacts(args.reference_build), "candidate": artifacts(args.candidate_build)}
    identities = {label: {name: {"path": str(path), "sha256": digest(path)}
                           for name, path in pair.items()} for label, pair in pairs.items()}
    args.output.mkdir(parents=True, exist_ok=False)
    receipt = {"schema": "ascent.rayon-phase-control.v1", "host": platform.platform(),
               "logical_cpus": os.cpu_count(), "source_heads": source_heads,
               "dependency_sha256": digest(Path("rust/Cargo.lock")), "executables": identities,
               "harness_sha256": digest(Path(__file__)),
               "row_harness_sha256": digest(Path(MATRIX.__file__)),
               "scope": "fixed ABBA, original large workload, 12 clients, 5 samples and 30s soak; no global speedup theorem",
               "work_distribution": os.environ.get("ASCENT_WORK_DISTRIBUTION", "adaptive"), "runs": []}
    for threads in (12, 1):
        for ordinal, label in enumerate(("reference", "candidate", "candidate", "reference")):
            output = args.output / f"t{threads}-{ordinal}-{label}"
            output.mkdir()
            row = MATRIX.run_case(SimpleNamespace(output=output, benchmark=pairs[label]["process_throughput"],
                                                 worker=pairs[label]["ascent-scheme-worker"]),
                                  ("parallel-closure", 24, 256, 16), ("rayon", 1, threads),
                                  receipt["work_distribution"])
            row.update(arm=ordinal, implementation=label)
            if row["valid"]:
                row["soak_throughput_per_second"] = float(row["soak"][0]["throughput_per_s"])
                for bound in ("lower", "upper"):
                    row[f"soak_p95_{bound}_ms"] = int(row["soak"][0][f"p95_{bound}_ns"]) / 1e6
            receipt["runs"].append(row)
            (args.output / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
    hashes = [{sample["sample"]: sample["answer_sha"] for sample in row["samples"]}
              for row in receipt["runs"]]
    matched = len(hashes) == 8 and len(hashes[0]) == 5 and all(value == hashes[0] for value in hashes)
    receipt["matched_complete_answers"] = matched
    receipt["executables_current"] = all(digest(pairs[label][name]) == item["sha256"]
                                          for label, pair in identities.items() for name, item in pair.items())
    receipt["complete"] = matched and receipt["executables_current"] and all(row["valid"] for row in receipt["runs"])
    if receipt["complete"]:
        receipt["comparisons"] = []
        for threads in (12, 1):
            rows = [row for row in receipt["runs"] if row["rust_threads"] == threads]
            for metric in ("median_throughput_per_second", "median_p95_request_ms",
                           "soak_throughput_per_second", "soak_p95_lower_ms", "soak_p95_upper_ms"):
                values = {label: [row[metric] for row in rows if row["implementation"] == label]
                          for label in pairs}
                receipt["comparisons"].append({"threads": threads, "metric": metric, "arms": values,
                    "candidate_over_reference": statistics.mean(values["candidate"]) / statistics.mean(values["reference"])})
    (args.output / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
    if not receipt["complete"]:
        raise SystemExit("incomplete or contaminated control; every arm retained")


if __name__ == "__main__":
    main()
