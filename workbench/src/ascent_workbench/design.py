# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Check development contracts through the pinned OpenSysML Python API."""
from contextlib import contextmanager
from dataclasses import asdict, dataclass
import hashlib
from importlib.metadata import version
import json
from pathlib import Path
import signal
import subprocess
import tempfile

import opensysml

ROOT = Path(__file__).resolve().parents[3]
MODELS = tuple(ROOT / "dev/sysml" / name for name in (
    "development.sysml", "dsl-contracts.sysml", "matching-state.sysml"))


@dataclass(frozen=True)
class Fixture:
    subject: str
    assertions: tuple[str, ...]
    failure: str | None = None


def fixtures():
    """The original matching fixtures plus the three DSL workstreams."""
    groups = (
        ("AscentDevelopment", "CompletionClaim", ("sourceEvidenceRequired", "measurementRequired"),
         ("openObligations",), {"prematureSourceClosure": "sourceEvidenceRequired",
                                "unmeasuredSpeedup": "measurementRequired"}),
        ("AscentDsl", "RelationRole", ("declaredUpdatePermission", "declaredHeadPermission"),
         ("inputUpdate", "hiddenInput", "derivedUpdateRejected", "mixedRelation"),
         {"illegalDerivedUpdate": "declaredUpdatePermission", "leakedWriteHandle": "declaredUpdatePermission",
          "illegalInputHead": "declaredHeadPermission"}),
        ("AscentDsl", "FiniteClosure", ("finiteHeightPremises", "budgetIsNotCompletion", "executionRemainsBounded"),
         ("boundedDomain", "exhaustedFinite", "guardedUnbounded"),
         {"budgetAsTermination": "finiteHeightPremises", "truncatedPublication": "budgetIsNotCompletion",
          "droppedBudget": "executionRemainsBounded"}),
        ("AscentDsl", "DiagnosticTransport", ("verdictPreserved", "originRetained", "observationOrder", "rejectionNotRunnable"),
         ("mappedRejection",), {"swallowedFailure": "verdictPreserved", "lostOrigin": "originRetained",
                                "reorderedGetter": "observationOrder", "runnableRejection": "rejectionNotRunnable"}),
        ("AscentMatching", "ReuseDecision", ("completedRead", "semanticIdentity", "everyPrefixDependency"),
         ("sameCut",), {"staleSecondSource": "everyPrefixDependency", "staleSecondDelta": "everyPrefixDependency",
                        "wrongOwner": "semanticIdentity", "incompletePrefix": "completedRead"}),
        ("AscentMatching", "BranchPublication", ("immutableSharing", "mutableIsolation", "completePublication"),
         ("matchingOnly", "newSuffix"), {"lostSupport": "completePublication", "skippedSuffix": "completePublication",
                                         "sharedMutation": "mutableIsolation", "canceledPublication": "completePublication"}),
        ("AscentMatching", "TransitionRead", ("exactTransitionRead",), ("transitionReplay",),
         {"effectfulReuse": "exactTransitionRead", "changedBinding": "exactTransitionRead",
          "staleLocalCut": "exactTransitionRead", "cachedCallerSupport": "exactTransitionRead"}),
        ("AscentMatching", "RetentionPolicy", ("boundedRetention", "exactFallback", "separateBudgets"),
         ("streamingAtCapacity",), {"overCapacity": "boundedRetention", "droppedFallback": "exactFallback"}),
    )
    for package, owner, assertions, positive, negative in groups:
        names = tuple(f"{package}::{owner}::{name}" for name in assertions)
        for subject in positive:
            yield Fixture(f"{package}::{subject}", names)
        for subject, failure in negative.items():
            yield Fixture(f"{package}::{subject}", names, f"{package}::{owner}::{failure}")


@contextmanager
def deadline(seconds=30):
    """Bound each API operation on the supported macOS/Linux development hosts."""
    def expired(_signum, _frame):
        raise TimeoutError(f"OpenSysML operation exceeded {seconds} seconds")

    previous = signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)


def check_validation(fixture, validation):
    """Require exact assertion identities and a decided, complete object walk."""
    validation.raise_for_error()
    summary = validation.summary
    if validation.bounded or summary is None or summary.error:
        raise ValueError(f"incomplete object validation: {fixture.subject}")
    if summary.element_id != fixture.subject or summary.kind != "object" or summary.instance_id <= 0:
        raise ValueError(f"wrong validated object: {fixture.subject}")
    actual = [verdict.element_id for verdict in validation]
    if len(actual) != len(fixture.assertions) or set(actual) != set(fixture.assertions):
        raise ValueError(f"missing, extra or duplicate assertion: {fixture.subject}: {actual}")
    for verdict in validation:
        if verdict.kind != "constraint" or verdict.instance_id != summary.instance_id or verdict.instance_path:
            raise ValueError(f"wrong assertion subject: {verdict.element_id}")
        if verdict.error or verdict.status not in ("holds", "violated"):
            raise ValueError(f"undecided assertion: {verdict.element_id}")
        if verdict.holds != (verdict.status == "holds"):
            raise ValueError(f"inconsistent assertion verdict: {verdict.element_id}")
    failures = [verdict.element_id for verdict in validation if not verdict.holds]
    expected = [] if fixture.failure is None else [fixture.failure]
    if failures != expected:
        raise ValueError(f"wrong failed assertion: {fixture.subject}: {failures}")
    if summary.holds != (not expected) or summary.status != ("holds" if not expected else "violated"):
        raise ValueError(f"inconsistent object verdict: {fixture.subject}")


def validation_record(validation):
    def verdict_record(verdict):
        return {key: getattr(verdict, key) for key in (
            "element_id", "kind", "holds", "status", "error", "condition", "instance_id", "instance_path")}

    return {"bounded": validation.bounded, "diagnostics": [str(d) for d in validation.diagnostics],
            "summary": None if validation.summary is None else verdict_record(validation.summary),
            "assertions": [verdict_record(verdict) for verdict in validation]}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def main():
    receipts = ROOT / ".cache/ascent/design-checks"
    receipts.mkdir(parents=True, exist_ok=True)
    receipt = Path(tempfile.mkdtemp(prefix="run.", dir=receipts))
    print(f"Design evidence: {receipt}", flush=True)
    inputs = (*MODELS, Path(__file__).resolve(), ROOT / "dev/sysml/workflow.org",
              ROOT / "workbench/pyproject.toml", ROOT / "workbench/uv.lock", ROOT / ".github/workflows/design.yml")
    identities = {str(path.relative_to(ROOT)): digest(path) for path in inputs}
    write_json(receipt / "inputs.json", identities)
    completed = []
    try:
        if version("opensysml") != "0.10.1":
            raise ValueError("unqualified OpenSysML client version")
        for args, name in ((["rev-parse", "HEAD"], "head.txt"), (["status", "--porcelain"], "worktree.txt")):
            (receipt / name).write_text(subprocess.check_output(["git", *args], cwd=ROOT, text=True, timeout=5))
        # Connection owns startup, release checks and cleanup; no CLI/JSON adapter.
        with opensysml.connect(version="v0.10.1") as connection:
            with deadline():
                info = connection.server_info()
                write_json(receipt / "tool.json", {"client": version("opensysml"), "service": info.version,
                           "origin": info.origin, "capabilities": sorted(info.capabilities)})
                model = connection.parse_sources([str(path) for path in MODELS],
                                                 strict=True, strict_conformance=True)
                write_json(receipt / "structure.json", {"ok": model.ok,
                           "diagnostics": [str(d) for d in model.diagnostics]})
                if not model.ok:
                    raise ValueError("model structure rejected")
            for fixture in fixtures():
                with deadline():
                    validation = model.validate_instance(fixture.subject)
                write_json(receipt / (fixture.subject.replace("::", "-") + ".json"),
                           {"fixture": asdict(fixture), "validation": validation_record(validation)})
                check_validation(fixture, validation)
                completed.append(fixture.subject)
                print(f"CHECKED {fixture.subject} {fixture.failure or 'holds'}", flush=True)
        if identities != {str(path.relative_to(ROOT)): digest(path) for path in inputs}:
            raise ValueError("design inputs changed during checking")
        write_json(receipt / "result.json", {"status": "passed", "completed": completed,
                   "scope": "architecture-only", "source_refinement": False, "performance_admitted": False})
        print(f"DESIGN-CONTRACTS-OK {len(completed)} objects; architecture only, no source/performance admission")
        return 0
    except Exception as error:
        write_json(receipt / "result.json", {"status": "failed", "completed": completed,
                   "error": f"{type(error).__name__}: {error}"})
        print(f"DESIGN-CONTRACTS-FAIL {type(error).__name__}: {error}", flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
