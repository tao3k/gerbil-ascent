# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Downstream formal qualification: original obligations, native capacity, exact exits."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, replace
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import time
import uuid

from .formal_models import CONFIGURATIONS, FAULTS, MODEL_ORDER

ROOT = Path.cwd().resolve()
SECONDS = 15 * 60
GROUPS = {
    "Nonmembership": (
        "CertificateMaterial", "TerminalTraversal", "ExecutionFeedback", "Withholding",
        "ProofShapeAdmission", "ProofPrefix", "CountProbe", "NegativeProbe", "NumericProbe",
        "PositiveNonmembershipSession", "SessionTransaction", "SessionPublication",
    ),
    "ProviderViews": (
        "ProviderViews", "ReaderLifetime", "RectangleExport", "RectangleCompaction",
        "WeightedExport", "OwnedLookup",
    ),
}


@dataclass(frozen=True)
class Configuration:
    model: str
    main: str
    constants: str
    invariants: tuple[str, ...]
    properties: tuple[str, ...] = ()
    specification: str = ""
    constraint: str = ""

    def qualified(self, name: str) -> str:
        return name if self.main == self.model else f"{self.main}_{self.model}_{name}"

    def text(self) -> str:
        start = f"SPECIFICATION {self.specification}\n" if self.specification else "INIT q_init\nNEXT q_step\n"
        result = start + f"CONSTANTS\n{self.constants}\nCHECK_DEADLOCK FALSE\n"
        if self.invariants:
            result += "INVARIANTS " + " ".join(map(self.qualified, self.invariants)) + "\n"
        if self.properties:
            result += "PROPERTIES " + " ".join(self.properties) + "\n"
        if self.constraint:
            result += f"CONSTRAINT {self.constraint}\n"
        return result

    def changed(self, **constants: object) -> Configuration:
        text = self.constants
        for name, value in constants.items():
            literal = ("TRUE" if value else "FALSE") if isinstance(value, bool) else str(value)
            text, count = re.subn(rf"(?m)^{re.escape(name)} = .*", f"{name} = {literal}", text)
            if count != 1:
                raise ValueError(f"missing or duplicate constant {self.model}.{name}")
        return replace(self, constants=text)


@dataclass(frozen=True)
class Obligation:
    name: str
    configuration: Configuration
    expected: int = 0
    property: str = ""


def configuration(model: str, environment: dict[str, str]) -> Configuration:
    common = environment.get("ASCENT_FORMAL_GENERATION_CUTOFF")
    bounds = {
        "cutoff": common or "2", "views_cutoff": common or "3",
        "actor_cutoff": environment.get("ASCENT_FORMAL_ACTOR_GENERATION_CUTOFF", "2"),
        "round_cutoff": environment.get("ASCENT_FORMAL_ROUND_CUTOFF", "4"),
        "session_cutoff": environment.get("ASCENT_FORMAL_SESSION_GENERATION_CUTOFF", "4"),
    }
    if any(re.fullmatch(r"[0-9]+", value) is None or int(value) < 2 for value in bounds.values()):
        raise ValueError("invalid finite exploration bound")
    if int(bounds["round_cutoff"]) < 3 or int(bounds["session_cutoff"]) < 3:
        raise ValueError("round and session exploration bounds must be at least three")
    fields = CONFIGURATIONS[model]
    constants = re.sub(r"\$(\w+)", lambda match: bounds[match[1]], fields["constants"])
    return Configuration(model, fields.get("main", model), constants,
                         tuple(fields["invariants"].split()), tuple(fields.get("properties", "").split()),
                         fields.get("specification", ""), fields.get("constraint", ""))


def obligations(base: Configuration) -> tuple[Obligation, ...]:
    model = base.model
    result = [Obligation("correct", base)]
    for mutation, property_name, expected in FAULTS.get(model, ()):
        constants = {}
        for name in ("Mutation", "Fault"):
            if re.search(rf"(?m)^{name} = ", base.constants):
                constants[name] = json.dumps(mutation)
        if "EarlyReturn = FALSE" in base.constants:
            constants["EarlyReturn"] = True
        fault = base.changed(**constants)
        if model == "ProviderFrontier" and mutation == "initial":
            fault = fault.changed(Seeded=True)
        if model == "LatticeProjection" and mutation in ("budget-skip", "budget-events", "refusal-publish"):
            fault = fault.changed(Remaining=1)
        fault = replace(fault, invariants=(property_name,) if expected == 12 else (),
                        properties=(fault.qualified(property_name),) if expected == 13 else ())
        result.append(Obligation(mutation, fault, expected, fault.qualified(property_name)))
    arithmetic_faults = {"EvidenceInteraction": ("negative-cost", "negative-events"),
                         "EvidenceConsumption": ("negative-cost", "future-snapshot")}
    for mutation in arithmetic_faults.get(model, ()):
        fault = replace(base.changed(Mutation=json.dumps(mutation)), invariants=("Safety",), properties=())
        result.append(Obligation(mutation, fault, 12, "Safety"))
    if model in ("ActorRoundCredits", "ActorTestPool", "ReadyComponents"):
        result.extend(Obligation(f"capacity-{n}", base.changed(Capacity=n)) for n in (1, 3))
    if model == "LatticeProjection":
        result.extend(Obligation(f"remaining-{n}", base.changed(Remaining=n)) for n in (0, 1))
    if model == "EvidenceLifecycle":
        result.append(Obligation("caller-finite", base.changed(InputLimit=1)))
    if model == "ProviderFrontier":
        result.extend((Obligation("seeded", base.changed(Seeded=True)),
                       Obligation("overlap", base.changed(Fault='"overlap"'))))
    if model == "WithdrawalConcurrency":
        successor = base.changed(SecondExpected=1)
        result.extend((Obligation("successor", successor),
                       Obligation("late-receipt", successor.changed(Mutation='"lateReceipt"'), 12, "ReceiptBound")))
    if model == "OrdinalIndex":
        result.append(Obligation("small-native-limit", base.changed(NativeLimit=16)))
    if model == "ReaderLifetime":
        result.append(Obligation("single-reader-global-fairness", base.changed(Readers="{1}", Mutation='"global"')))
        round_config = replace(base, specification="roundSpec", properties=("ReaderCompletion", "RoundCompletion"))
        result.append(Obligation("sealed-round", round_config))
        unfair = replace(round_config.changed(Mutation='"unfair"'), invariants=(), properties=("RoundCompletion",))
        result.append(Obligation("sealed-round-unfair", unfair, 13, "RoundCompletion"))
    return tuple(result)


def validate_output(obligation: Obligation, code: int, output: str) -> None:
    if code != obligation.expected:
        raise RuntimeError(f"{obligation.name}: exit={code} expected={obligation.expected}\n{output}")
    if code == 0:
        valid = "Model checking completed. No error has been found." in output
    elif code == 12:
        valid = f"Invariant {obligation.property} is violated" in output
    else:
        valid = bool(re.search(rf"Temporal propert(y {re.escape(obligation.property)} was|ies were) violated|"
                               rf"Action property {re.escape(obligation.property)} is violated", output))
    if not valid:
        raise RuntimeError(f"missing checker conclusion for {obligation.name}\n{output}")


def capacity(heap_mib: int = 1024) -> int:
    ceiling = os.environ.get("ASCENT_FORMAL_WORKERS")
    if ceiling is not None and (not ceiling.isdecimal() or int(ceiling) < 1):
        raise ValueError("ASCENT_FORMAL_WORKERS must be a positive integer")
    cpu = len(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else (os.cpu_count() or 1)
    quota = Path("/sys/fs/cgroup/cpu.max")
    if quota.exists():
        amount, period = quota.read_text().split()
        if amount.isdecimal():
            cpu = min(cpu, max(1, (int(amount) + int(period) - 1) // int(period)))
    memory = os.sysconf("SC_PHYS_PAGES") * os.sysconf("SC_PAGE_SIZE") if sys.platform != "darwin" else int(
        subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True))
    path = Path("/sys/fs/cgroup/memory.max")
    if path.exists() and path.read_text().strip().isdecimal():
        memory = min(memory, int(path.read_text()))
    # A 1 GiB TLC heap plus native overhead; leave room for Lean and the OS.
    detected = max(1, min(cpu, max(1, (memory - 2 * 1024**3) // ((heap_mib + 256) * 1024**2))))
    # A caller may reduce concurrency without changing any model or obligation.
    return detected if ceiling is None else min(detected, int(ceiling))


def verification_schedule(configurations: list[Configuration]) -> list[Configuration]:
    # Every model is already compiled and independent. Start larger obligation
    # groups first so their serial checks do not form a late verification tail.
    return sorted(configurations, key=lambda base: len(obligations(base)), reverse=True)


class Runner:
    def __init__(self) -> None:
        self.started = time.monotonic()
        self.deadline = self.started + SECONDS
        supplied = os.environ.get("ASCENT_FORMAL_RUN_DIR")
        self.output = Path(supplied) if supplied else ROOT / ".cache/ascent/formal" / uuid.uuid4().hex
        self.output.mkdir(parents=True, exist_ok=False)
        self.environment = dict(os.environ, QUINT_HOME=str(ROOT / ".cache/ascent/tools/quint-backends"),
                                OUT_DIR=str(ROOT / ".cache/ascent/quint-output"))
        for name in ("no_proxy", "NO_PROXY"):
            self.environment[name] = "127.0.0.1,localhost" + ("," + os.environ[name] if os.environ.get(name) else "")
        self.quint = ROOT / ".cache/ascent/tools/quint/node_modules/.bin/quint"
        self.jar = Path(self.environment["QUINT_HOME"]) / "apalache-dist-0.62.1/apalache/lib/apalache.jar"
        self.server: subprocess.Popen | None = None

    def run(self, argv: list[str], label: str, cwd: Path = ROOT) -> tuple[int, str]:
        path = self.output / f"{label}.out"
        guarded = bool(argv and Path(argv[0]).name == "lake")
        if guarded:
            adapter = [sys.executable, str(ROOT / "workbench/src/ascent_workbench/lean_guard.py")]
            if argv[1:] == ["-v", "build", "AscentProof", "AscentProofTests"]:
                argv = [*adapter, "build"]
            elif (argv[1:4] == ["env", "lean", "--run"] and
                  (len(argv) == 6 or (len(argv) > 6 and argv[4:6] == ["ExecutionPolicy.lean", "batch"]))):
                argv = [*adapter, "render", *argv[4:]]
            else:
                raise ValueError("unsupported Lean invocation; use the source-owned Guard adapter")
        errors = self.output / f"{label}.stderr.out"
        with path.open("w") as log, errors.open("w") as diagnostics:
            child = subprocess.Popen(argv, cwd=cwd, env=self.environment, stdout=log,
                                     stderr=diagnostics if guarded else subprocess.STDOUT,
                                     start_new_session=True)
            try:
                code = child.wait(timeout=max(0, self.deadline - time.monotonic()))
            except BaseException:
                if child.poll() is None:
                    # The LeanPoo adapter owns a nested compiler group. Give its
                    # finally cleanup a chance to reap that group before killing
                    # the adapter itself, as in LeanPoo's phase supervisor.
                    os.killpg(child.pid, signal.SIGTERM)
                    try:
                        child.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(child.pid, signal.SIGKILL)
                        child.wait()
                raise
        return code, path.read_text() + (errors.read_text() if code and guarded else "")

    def start_compiler(self) -> int:
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        self.server_log = (self.output / "compiler.out").open("w")
        self.server = subprocess.Popen(["java", "-Xmx1G", "-Xss32m", "-XX:+UseParallelGC",
                                      f"-Djava.io.tmpdir={self.output}", "-jar", str(self.jar),
                                      "server", f"--port={port}"], cwd=ROOT, env=self.environment,
                                      stdout=self.server_log, stderr=subprocess.STDOUT)
        ready_deadline = min(self.deadline, time.monotonic() + 30)
        while self.server.poll() is None and time.monotonic() < ready_deadline:
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                    return port
            except OSError:
                time.sleep(0.1)
        raise RuntimeError("Quint compiler did not start: " + (self.output / "compiler.out").read_text())

    def close_compiler(self) -> None:
        if self.server is not None:
            if self.server.poll() is None:
                self.server.terminate()
            try:
                self.server.wait(timeout=1)
            except subprocess.TimeoutExpired:
                self.server.kill()
                self.server.wait()
            self.server_log.close()
            self.server = None

    def compile(self, configurations: list[Configuration]) -> None:
        cache = ROOT / ".cache/ascent/quint-compiled"
        cache.mkdir(parents=True, exist_ok=True)
        # Imported helpers are compilation inputs too. No model-check results
        # are cached; even a compilation hit must execute every obligation.
        inputs = [(str(p.relative_to(ROOT)), hashlib.sha256(p.read_bytes()).hexdigest())
                  for p in sorted((ROOT / "packages/proofs/quint").glob("*.qnt"))]
        inputs += [("package-lock", hashlib.sha256((ROOT / "packages/proofs/quint/package-lock.json").read_bytes()).hexdigest()),
                   ("backend", hashlib.sha256(self.jar.read_bytes()).hexdigest())]
        port = None
        try:
            for base in configurations:
                temporal = ("ReaderCompletion", "RoundCompletion", "spec", "roundSpec") if base.model == "ReaderLifetime" else base.properties
                fingerprint = hashlib.sha256(json.dumps((inputs, base.main, base.invariants, temporal, base.constraint)).encode()).hexdigest()
                identity, artifact = cache / f"{base.model}.identity", cache / f"{base.model}.tla"
                target = self.output / f"{base.main}.tla"
                hit = False
                if identity.exists() and artifact.exists():
                    fields = identity.read_text().split()
                    hit = fields == [fingerprint, hashlib.sha256(artifact.read_bytes()).hexdigest()]
                if hit:
                    target.write_bytes(artifact.read_bytes())
                else:
                    if port is None:
                        port = self.start_compiler()
                    invariants = (*base.invariants, *((base.constraint,) if base.constraint else ()))
                    argv = [str(self.quint), "compile", f"packages/proofs/quint/{base.model}.qnt", "--main", base.main,
                            "--target", "tlaplus", "--init", "init", "--step", "step", "--invariant", ",".join(invariants),
                            "--apalache-version", "0.62.1", "--server-endpoint", f"127.0.0.1:{port}", "--verbosity", "0"]
                    if temporal:
                        argv += ["--temporal", ",".join(temporal)]
                    code, output = self.run(argv, f"compile-{base.model}")
                    if code or f"MODULE {base.main} " not in output:
                        raise RuntimeError(f"Quint compilation failed {base.model}: {output}")
                    artifact.write_text(output)
                    identity.write_text(f"{fingerprint} {hashlib.sha256(artifact.read_bytes()).hexdigest()}\n")
                    target.write_text(output)
                target.write_text(re.sub(r'"(?:\\.|[^"\\])*"|:=', lambda match: "=" if match[0] == ":=" else match[0], target.read_text()))
                print(f"QUINT-COMPILE-OK {base.model} cache={int(hit)}", flush=True)
        finally:
            self.close_compiler()

    def check(self, base: Configuration) -> int:
        count = 0
        checks = obligations(base)
        print(f"QUINT-MODEL-START {base.model} obligations={len(checks)}", flush=True)
        for obligation in checks:
            label = f"{base.model}-{obligation.name}"
            config = self.output / f"{label}.cfg"
            config.write_text(obligation.configuration.text())
            code, output = self.run(["java", "-Xmx1G", "-XX:+UseParallelGC", f"-Djava.io.tmpdir={self.output}",
                                     "-cp", str(self.jar), "tlc2.TLC", "-workers", "1", "-config", str(config),
                                     "-metadir", str(self.output / label), str(self.output / f"{base.main}.tla")], label)
            validate_output(obligation, code, output)
            marker = "QUINT-CHECK-OK" if code == 0 else "COUNTEREXAMPLE-OK"
            print(f"{marker} {label} {obligation.property} exit={code}", flush=True)
            count += 1
        return count

    def quint_checks(self, models: tuple[str, ...]) -> dict[str, int]:
        configurations = [configuration(model, self.environment) for model in models]
        self.compile(configurations)
        workers = min(capacity(), len(configurations))
        print(f"QUINT-CAPACITY workers={workers} models={len(configurations)}", flush=True)
        results = {}
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {pool.submit(self.check, base): base.model for base in verification_schedule(configurations)}
            for future in as_completed(futures):
                results[futures[future]] = future.result()
        print("ALL-QUINT-CHECK-OK", flush=True)
        return results



def renderings_from_batch(output: str, languages: list[str]) -> dict[str, str]:
    """Keep every named source comparison; batching only avoids Lean restarts."""
    try:
        rows = json.loads(output)
    except (json.JSONDecodeError, TypeError) as error:
        raise RuntimeError('malformed Lean source rendering batch') from error
    if (not isinstance(rows, list) or any(not isinstance(row, list) or len(row) != 2
            or not all(isinstance(value, str) for value in row) for row in rows)):
        raise RuntimeError('malformed Lean source rendering rows')
    result = dict(rows)
    if len(result) != len(rows) or set(result) != set(languages):
        raise RuntimeError('missing, duplicate or extra Lean source rendering')
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("all", "quint"))
    parser.add_argument("group", nargs="?", default="all")
    args = parser.parse_args()
    if args.mode == "all" and args.group != "all":
        parser.error("full formal verification requires the complete inventory")
    models = tuple(MODEL_ORDER) if args.group == "all" else GROUPS.get(args.group, (args.group,))
    if any(model not in MODEL_ORDER for model in models):
        parser.error("unknown Quint feature")
    runner = Runner()
    try:
        if args.mode == "all":
            code, output = runner.run(
                [sys.executable, "-m", "unittest", "discover", "-s", "packages/proofs/tests",
                 "-p", "test_lean_guard.py"], "lean-guard-tests")
            if code:
                raise RuntimeError("LeanPoo Guard regressions failed: " + output)
            print("LEAN-GUARD-TESTS-OK", flush=True)
            with ThreadPoolExecutor(max_workers=1) as independent:
                lean = independent.submit(runner.run, ["lake", "-v", "build", "AscentProof", "AscentProofTests"], "lean", ROOT / "packages/proofs/lean")
                results = runner.quint_checks(models)
                code, output = lean.result()
                if code:
                    raise RuntimeError("Lean failed: " + output)
            # Compare generated executable definitions, not source digests or
            # captured test outputs. Runtime and Quint import these exact files.
            renderings = (
                ("ExecutionPolicy.lean", "snapshot", "program/scheme-snapshot.ss"),
                ("ExecutionPolicy.lean", "snapshot-quint", "packages/proofs/quint/ClosedDslLowering.qnt"),
                ("ExecutionPolicy.lean", "archive-cache", ".github/workflows/ci.yml"),
                ("ExecutionPolicy.lean", "row-view-scheme", "program/types.ss"),
                ("ExecutionPolicy.lean", "borrowed-match-rust", "rust/ascent/src/execution/matching.rs"),
                ("ExecutionPolicy.lean", "borrowed-match-scheme", "program/rust-execution.ss"),
                ("ExecutionPolicy.lean", "ranked-row-rust", "rust/ascent/src/execution/ordering.rs"),
                ("ExecutionPolicy.lean", "archive-rust", "rust/ascent-build/src/policy.rs"),
                ("ExecutionPolicy.lean", "archive-quint", "packages/proofs/quint/ArchivePolicy.qnt"),
                ("ExecutionPolicy.lean", "scheme", "core/execution-policy.ss"),
                ("ExecutionPolicy.lean", "rust", "rust/ascent/src/execution/policy.rs"),
                ("ExecutionPolicy.lean", "proof-authority-rust", "rust/ascent-scheme/src/api/session.rs"),
                ("ExecutionPolicy.lean", "ordinal-extent-rust", "rust/ascent/src/execution/ordinal.rs"),
                ("ExecutionPolicy.lean", "capacity-rust", "rust/ascent/src/execution/work.rs"),
                ("ExecutionPolicy.lean", "capacity-quint", "packages/proofs/quint/RequestScheduling.qnt"),
                ("ExecutionPolicy.lean", "stage-fanout-rust", "rust/ascent/src/execution/kernels.rs"),
                ("ExecutionPolicy.lean", "stage-link-rust", "rust/ascent/src/session.rs"),
                ("ExecutionPolicy.lean", "stage-fanout-quint", "packages/proofs/quint/RequestScheduling.qnt"),
                ("ExecutionPolicy.lean", "checkpoint-rust", "rust/ascent-scheme/src/process_policy.rs"),
                ("ExecutionPolicy.lean", "wait-result-rust", "rust/ascent-scheme/tests/unit/checkpoint_transport_darwin.rs"),
                ("ExecutionPolicy.lean", "wait-result-quint", "packages/proofs/quint/CheckpointTransport.qnt"),
                ("ExecutionPolicy.lean", "checkpoint-flags-rust", "rust/ascent-scheme/tests/unit/checkpoint_transport.rs"),
                ("ExecutionPolicy.lean", "checkpoint-wait-rust", "rust/ascent-scheme/tests/unit/checkpoint_transport.rs"),
                ("ExecutionPolicy.lean", "checkpoint-publish-rust", "rust/ascent-scheme/tests/unit/checkpoint_transport.rs"),
                ("ExecutionPolicy.lean", "checkpoint-cost-quint", "packages/proofs/quint/CheckpointTransport.qnt"),
                ("ExecutionPolicy.lean", "quint", "packages/proofs/quint/ExecutionPolicy.qnt"),
                ("ExecutionPolicy.lean", "preparation-python", "workbench/src/ascent_workbench/preparation_policy.py"),
                ("ExecutionPolicy.lean", "preparation-quint", "packages/proofs/quint/PreparationPolicy.qnt"),
                ("ExecutionPolicy.lean", "preparation-selection", "t/harness/build.ss"),
                ("ExecutionPolicy.lean", "preparation-interface-quint", "packages/proofs/quint/PreparationInterfaces.qnt"),
                ("ExecutionPolicy.lean", "preparation-interfaces", "t/harness/library-spec.ss"),
                ("ExecutionPolicy.lean", "preparation-import", "t/harness/build.ss"),
                ("ExecutionPolicy.lean", "compiler-quint", "packages/proofs/quint/CompilerPolicy.qnt"),
                ("ExecutionPolicy.lean", "row-decode-rust", "rust/ascent/src/execution/values.rs"),
                ("ExecutionPolicy.lean", "row-cost-quint", "packages/proofs/quint/OwnedLookup.qnt"),
                ("ExecutionPolicy.lean", "lookup-materialization", "core/relation-view.ss"),
                ("ExecutionPolicy.lean", "lookup-admission", "core/relation-view.ss"),
                ("ExecutionPolicy.lean", "lookup-study-profile", "t/performance/run.ss"),
                ("ExecutionPolicy.lean", "preparation-cc-observed", "workbench/src/ascent_workbench/preparation_work.py"),
                ("ExecutionPolicy.lean", "preparation-compiler", "build-modules.ss"),
                ("ExecutionPolicy.lean", "preparation-options", "t/harness/artifact-admission.ss"),
                ("ExecutionPolicy.lean", "preparation-stale", "t/harness/library-spec.ss"),
                ("ExecutionPolicy.lean", "preparation-coverage", "workbench/src/ascent_workbench/preparation_work.py"),
                ("ExecutionPolicy.lean", "preparation-runtime-env", "tools/ci/build-cost-control.py"),
                ("ExecutionPolicy.lean", "preparation-pass-total", "workbench/src/ascent_workbench/preparation_work.py"),
                ("ExecutionPolicy.lean", "preparation-ggc", "workbench/src/ascent_workbench/preparation_work.py"),
                ("ExecutionPolicy.lean", "preparation-restore-inputs", ".github/workflows/build-cost.yml"),
                ("ExecutionPolicy.lean", "preparation-cache-admission", ".github/workflows/build-cost.yml"),
                ("ExecutionPolicy.lean", "preparation-cache-inputs", ".github/workflows/build-cost.yml"),
                ("ExecutionPolicy.lean", "preparation-producer", "workbench/src/ascent_workbench/preparation_work.py"),
                ("ExecutionPolicy.lean", "preparation-support-admission", "t/harness/artifact-admission.ss"),
                ("ExecutionPolicy.lean", "preparation-value-shape", "program/types.ss"),
                ("ExecutionPolicy.lean", "preparation-metadata-guard", "program/types.ss"),
                ("ExecutionPolicy.lean", "owned-relation-value", "program/types.ss"),
                ("ExecutionPolicy.lean", "owned-aggregate-value", "program/types.ss"),
                ("ExecutionPolicy.lean", "aggregate-constructor", "program/objects.ss"),
                ("ExecutionPolicy.lean", "checkpoint-spin-policy", "rust/ascent-scheme/tests/unit/checkpoint_transport.rs"),
                ("ExecutionPolicy.lean", "checkpoint-publication-link", "rust/ascent-scheme/src/service.rs"),
                ("ExecutionPolicy.lean", "owner-control-rust", "rust/ascent-scheme/src/control_state.rs"),
                ("ExecutionPolicy.lean", "projection-object-reuse", "interface/projection-cache.ss"),
                ("ExecutionPolicy.lean", "projection-allocation-probe", "tools/ci/projection-allocation.ss"),
                ("ExecutionPolicy.lean", "owned-declaration-values", "program/types.ss"),
                ("ExecutionPolicy.lean", "owned-declaration-check", "program/objects.ss"),
                ("ExecutionPolicy.lean", "capture-row-transport", "program/operator-analysis.ss"),
                ("ExecutionPolicy.lean", "capture-mapping-indexes", "program/operator-change.ss"),
                ("ExecutionPolicy.lean", "preparation-output-target", "workbench/src/ascent_workbench/preparation_work.py"),
                ("ExecutionPolicy.lean", "preparation-job-allocation", "workbench/src/ascent_workbench/preparation_work.py"),
                ("ExecutionPolicy.lean", "preparation-audit-order", "tools/ci/build-cost-control.py"),
                ("ExecutionPolicy.lean", "preparation-projection-cache", "t/harness/artifact-admission.ss"),
                ("ExecutionPolicy.lean", "preparation-batch-width", "tools/ci/build-cost-control.py"),
                ("ExecutionPolicy.lean", "preparation-output-publication", "workbench/src/ascent_workbench/preparation_work.py"),
                ("ExecutionPolicy.lean", "preparation-source-coverage", "workbench/src/ascent_workbench/preparation_work.py"),
                ("ExecutionPolicy.lean", "preparation-modules-current", "t/harness/artifact-admission.ss"),
                ("ExecutionPolicy.lean", "preparation-parent", "workbench/src/ascent_workbench/preparation_work.py"),
                ("ExecutionPolicy.lean", "preparation-origin", "workbench/src/ascent_workbench/preparation_work.py"),
                ("ExecutionPolicy.lean", "preparation-inputs", "workbench/src/ascent_workbench/preparation_work.py"),
                ("ExecutionPolicy.lean", "preparation-source", "t/harness/library-spec.ss"),
                ("ExecutionPolicy.lean", "preparation-heap", "justfile"),
                ("ExecutionPolicy.lean", "preparation-runner", "justfile"),
                ("ExecutionPolicy.lean", "preparation-groups", "t/harness/test.ss"),
                ("ExecutionPolicy.lean", "dsl-select", "program/scheme-language.ss"),
                ("ExecutionPolicy.lean", "dsl-root", "program/objects.ss"),
                ("ExecutionPolicy.lean", "dsl-owned", "program/scheme-language.ss"),
                ("ExecutionPolicy.lean", "dsl-workload", "t/qualification/ascent-semi-naive-test.ss"),
                ("ExecutionPolicy.lean", "preparation-roots", "t/harness/library-spec.ss"),
                ("ExecutionPolicy.lean", "preparation-support", "packages/proofs/quint/PreparationSupport.qnt"),
                ("ExecutionPolicy.lean", "preparation-cargo-cache", ".github/workflows/ci.yml"),
                ("RenderDescriptor.lean", "scheme", "core/descriptor-stream.ss"),
                ("RenderDescriptor.lean", "rust", "rust/ascent/src/graph/descriptor_stream.rs"),
                ("RenderCache.lean", "scheme", "core/index-publication.ss"),
                ("RenderActor.lean", "scheme", "core/actor-envelope.ss"),
                ("RenderScc.lean", "scheme", "core/scc-state.ss"),
            )
            languages = [language for script, language, _ in renderings if script == "ExecutionPolicy.lean"]
            code, batch_output = runner.run(
                ["lake", "env", "lean", "--run", "ExecutionPolicy.lean", "batch", *languages],
                "ExecutionPolicy-batch", ROOT / "packages/proofs/lean")
            if code:
                raise RuntimeError("Lean source rendering batch failed: " + batch_output)
            batch = renderings_from_batch(batch_output, languages)
            for script, language, target in renderings:
                if script == "ExecutionPolicy.lean":
                    code, source = 0, batch[language]
                else:
                    code, source = runner.run(
                        ["lake", "env", "lean", "--run", script, language],
                        Path(script).stem + "-" + language, ROOT / "packages/proofs/lean")
                expected = (ROOT / target).read_text()
                if language == "archive-cache":
                    begin = "      # BEGIN GENERATED ARCHIVE CACHE\n"
                    end = "      # END GENERATED ARCHIVE CACHE\n"
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError("missing or duplicate archive cache region")
                    expected = expected.split(begin)[1].split(end)[0]
                elif language == "row-view-scheme":
                    begin, end = ';; BEGIN GENERATED OWNED ROW VIEW\n', ';; END GENERATED OWNED ROW VIEW\n'
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError("missing or duplicate owned row view source region")
                    expected = expected.split(begin)[1].split(end)[0]
                elif language.startswith("dsl-"):
                    region = language.removeprefix("dsl-").upper()
                    begin, end = f';; BEGIN GENERATED DSL-{region}\n', f';; END GENERATED DSL-{region}'
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError('missing or duplicate generated DSL region: ' + language)
                    expected = expected.split(begin)[1].split(end)[0]
                elif language == "proof-authority-rust":
                    begin, end = '        // BEGIN GENERATED PROOF AUTHORITY READ\n', '        // END GENERATED PROOF AUTHORITY READ\n'
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError("missing or duplicate proof authority read source region")
                    expected = expected.split(begin)[1].split(end)[0]
                elif language in {"borrowed-match-rust", "borrowed-match-scheme"}:
                    prefix = "//" if language.endswith("rust") else ";;"
                    begin, end = f"{prefix} BEGIN GENERATED BORROWED MATCH\n", f"{prefix} END GENERATED BORROWED MATCH\n"
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError("missing or duplicate borrowed matcher source region")
                    expected = expected.split(begin)[1].split(end)[0]
                elif language == "ranked-row-rust":
                    begin, end = '// BEGIN GENERATED RANKED ROW ORDER\n', '// END GENERATED RANKED ROW ORDER\n'
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError("missing or duplicate ranked row source region")
                    expected = expected.split(begin)[1].split(end)[0]
                elif language == "ordinal-extent-rust":
                    begin, end = '// BEGIN GENERATED ORDINAL EXTENT\n', '// END GENERATED ORDINAL EXTENT\n'
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError("missing or duplicate ordinal extent source region")
                    expected = expected.split(begin)[1].split(end)[0]
                elif language in {"capacity-rust", "capacity-quint"}:
                    indent = "  " if language == "capacity-quint" else ""
                    begin, end = (f'{indent}// BEGIN GENERATED FANOUT CAPACITY\n',
                                  f'{indent}// END GENERATED FANOUT CAPACITY\n')
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError("missing or duplicate fanout capacity source region")
                    expected = expected.split(begin)[1].split(end)[0]
                elif language in {"stage-fanout-rust", "stage-link-rust", "stage-fanout-quint"}:
                    marker = "LIVE LINK" if language == "stage-link-rust" else "LIVE FANOUT"
                    indent = "            " if language == "stage-link-rust" else "  " if language == "stage-fanout-quint" else ""
                    begin, end = (f'{indent}// BEGIN GENERATED {marker}\n',
                                  f'{indent}// END GENERATED {marker}\n')
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError("missing or duplicate live-stage source region")
                    expected = expected.split(begin)[1].split(end)[0]
                elif language in {"checkpoint-flags-rust", "checkpoint-wait-rust",
                                  "checkpoint-publish-rust", "checkpoint-cost-quint"}:
                    region = language.split("-")[1].upper()
                    indent = "  " if language == "checkpoint-cost-quint" else ""
                    begin, end = (f'{indent}// BEGIN GENERATED CHECKPOINT {region}\n',
                                  f'{indent}// END GENERATED CHECKPOINT {region}\n')
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError("missing or duplicate checkpoint source region")
                    expected = expected.split(begin)[1].split(end)[0]
                elif language in {"wait-result-rust", "wait-result-quint"}:
                    indent = "" if language == "wait-result-rust" else "  "
                    begin, end = (f'{indent}// BEGIN GENERATED WAIT RESULT\n',
                                  f'{indent}// END GENERATED WAIT RESULT\n')
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError("missing or duplicate wait-result source region")
                    expected = expected.split(begin)[1].split(end)[0]
                elif language in {"row-decode-rust", "row-cost-quint"}:
                    marker = "OWNED ROW" if language == "row-decode-rust" else "OWNED ROW COST"
                    indent = "    " if language == "row-decode-rust" else "  "
                    begin, end = (f'{indent}// BEGIN GENERATED {marker}\n',
                                  f'{indent}// END GENERATED {marker}\n')
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError('missing or duplicate owned row source region')
                    expected = expected.split(begin)[1].split(end)[0]
                elif language.startswith("lookup-"):
                    region = language.removeprefix("lookup-").upper()
                    begin, end = f';; BEGIN GENERATED LOOKUP {region}\n', f';; END GENERATED LOOKUP {region}\n'
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError('missing or duplicate lookup source region')
                    expected = expected.split(begin)[1].split(end)[0]
                elif language in {"owned-declaration-values", "owned-declaration-check", "owned-aggregate-value", "aggregate-constructor"}:
                    marker = language.upper().replace("-", " ")
                    begin, end = (f';; BEGIN GENERATED {marker}\n', f';; END GENERATED {marker}\n')
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError('missing or duplicate owned declaration region')
                    expected = expected.split(begin)[1].split(end)[0]
                elif language in {"checkpoint-spin-policy", "checkpoint-publication-link"}:
                    marker = language.upper().replace("-", " ")
                    begin, end = f'// BEGIN GENERATED {marker}\n', f'// END GENERATED {marker}\n'
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError('missing or duplicate checkpoint waiting source region')
                    expected = expected.split(begin)[1].split(end)[0]
                elif language in {"projection-allocation-probe", "owner-control-rust", "projection-object-reuse"}:
                    pass  # The complete diagnostic is source-bound, not its printed byte report.
                elif language == "owned-relation-value":
                    begin, end = (';; BEGIN GENERATED OWNED RELATION VALUE\n',
                                  ';; END GENERATED OWNED RELATION VALUE\n')
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError('missing or duplicate owned relation region')
                    expected = expected.split(begin)[1].split(end)[0]
                elif language == "capture-mapping-indexes":
                    begin, end = (';; BEGIN GENERATED CAPTURE MAPPING INDEXES\n',
                                  ';; END GENERATED CAPTURE MAPPING INDEXES\n')
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError('missing or duplicate captured mapping indexes region')
                    expected = expected.split(begin)[1].split(end)[0]
                elif language == "capture-row-transport":
                    begin, end = ('            ;; BEGIN GENERATED CAPTURE ROW TRANSPORT\n',
                                  '            ;; END GENERATED CAPTURE ROW TRANSPORT\n')
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError('missing or duplicate capture row transport region')
                    expected = expected.split(begin)[1].split(end)[0]
                elif language in {"preparation-metadata-guard", "preparation-value-shape", "preparation-runtime-env", "preparation-pass-total", "preparation-batch-width", "preparation-cc-observed", "preparation-modules-current", "preparation-source-coverage", "preparation-output-publication", "preparation-projection-cache", "preparation-audit-order", "preparation-output-target", "preparation-job-allocation", "preparation-restore-inputs", "preparation-cache-admission", "preparation-producer", "preparation-support-admission", "preparation-cache-inputs", "preparation-parent", "preparation-origin", "preparation-inputs", "preparation-stale", "preparation-coverage", "preparation-compiler", "preparation-options", "preparation-ggc", "preparation-interfaces", "preparation-selection", "preparation-import", "preparation-source", "preparation-runner", "preparation-groups", "preparation-roots", "preparation-cargo-cache", "preparation-heap"}:
                    region = language.removeprefix("preparation-").upper()
                    prefix = "#" if language in {"preparation-runtime-env", "preparation-pass-total", "preparation-batch-width", "preparation-cc-observed", "preparation-source-coverage", "preparation-output-publication", "preparation-audit-order", "preparation-output-target", "preparation-job-allocation", "preparation-producer", "preparation-parent", "preparation-coverage", "preparation-inputs"} else "    #" if language in {"preparation-ggc", "preparation-origin"} else "#" if language == "preparation-heap" else "        #" if language == "preparation-runner" else "          #" if language in {"preparation-restore-inputs", "preparation-cache-admission", "preparation-cache-inputs", "preparation-cargo-cache"} else ";;"
                    begin, end = (f'{prefix} BEGIN GENERATED PREPARATION {region}\n',
                                  f'{prefix} END GENERATED PREPARATION {region}\n')
                    if expected.count(begin) != 1 or expected.count(end) != 1:
                        raise RuntimeError('missing or duplicate generated preparation region: ' + language)
                    expected = expected.split(begin)[1].split(end)[0]
                if code or source != expected:
                    raise RuntimeError("execution policy rendering differs: " + target)
                print("EXECUTION-POLICY-OK " + target, flush=True)
            print("ALL-FORMAL-CHECK-OK", flush=True)
        else:
            results = runner.quint_checks(models)
        (runner.output / "receipt.json").write_text(json.dumps({"models": results, "complete": set(results) == set(models),
            "seconds": time.monotonic() - runner.started, "budgetSeconds": SECONDS}, indent=2) + "\n")
        return 0
    except Exception as failure:
        print(str(failure), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
