"""Matched installed-wheel C ABI/Rayon measurements; no inference in Python."""
import hashlib
import json
import statistics
import time
from pathlib import Path

import ascent._core
from ascent import Engine
from ascent.build import runtime_identity

SOURCE = """(define-evidence (matched-rayon)
 (sources left right) (outputs matched)
 (relation left ((x exact-integer?)))
 (relation right ((x exact-integer?)))
 (relation matched ((x exact-integer?)))
 ((matched X) <-- (left X) (right X)))"""
HEAVY = """(define-evidence (matched-compute)
 (sources input) (outputs summary)
 (relation input ((x exact-integer?)))
 (relation passed ((x exact-integer?)))
 (relation summary ((n exact-integer?)))
 ((passed X) <-- (input X) (if (X) (> (* X X) 0)))
 ((summary N) <-- (aggregate N gerbil-ascent-count () (passed X))))"""


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def measure(workers, rows, source, compute, result_format):
    started = time.perf_counter()
    cpu = time.process_time()
    engine = Engine(backend="rust", workers=workers)
    owner = engine.core_rules(source, trusted=True, diagnostics=True)
    try:
        runtime = owner.runtime().value()
        assert runtime["workers"] == workers and runtime["schemeVm"] is False
        owner.run().value()  # Existing replacement contract requires a completed run.
        ready = time.perf_counter()
        owner.replace({"input": rows} if compute else {"left": rows, "right": rows}).value()
        replaced = time.perf_counter()
        replacement_diagnostics = owner.diagnose().value()
        result = owner.run(result_format=result_format)
        answer = result.value()
        observed = time.perf_counter()
        assert answer["complete"] is True
        relation = answer["relations"]["summary" if compute else "matched"]
        numbers = ([row[0] for row in relation] if result_format=="typed-rows" else
                   [node["car"]["value"] for node in relation["nodes"]
                    if node["type"] == "pair" and node["car"].get("type") == "number"])
        assert sorted(map(int, numbers)) == ([len(rows)] if compute else [row[0] for row in rows])
        native_diagnostics = owner.diagnose().value()
        host_diagnostics = result.diagnose()
        result.close()
    finally:
        owner.close()
        engine.close()
    return {"workers": workers, "resultFormat":result_format, "totalSeconds": time.perf_counter() - started,
            "cpuSeconds": time.process_time() - cpu,
            "openSeconds": ready - started, "replacementSeconds": replaced - ready,
            "queryAndTransportSeconds": observed - replaced, "answerSHA": digest(sorted(map(int,numbers))),
            "replacementDiagnostics": replacement_diagnostics,
            "nativeDiagnostics": native_diagnostics, "hostDiagnostics": host_diagnostics}


def main():
    before = runtime_identity()
    cases = []
    for compute, size in ((False,4096),(False,16384),(True,4096),(True,16384)):
        source = HEAVY if compute else SOURCE
        rows = [[(1 << 1024) + i if compute else i] for i in range(size)]
        observations = []
        for pair in range(5):
            for workers in ((1, 4) if pair % 2 == 0 else (4, 1)):
                for result_format in (("graph","typed-rows") if pair%2==0 else ("typed-rows","graph")):
                    observations.append(measure(workers, rows, source, compute,result_format))
        assert len({run["answerSHA"] for run in observations}) == 1
        medians = {result_format: {str(workers): statistics.median(
            run["totalSeconds"] for run in observations if run["workers"] == workers and run["resultFormat"]==result_format
        ) for workers in (1,4)} for result_format in ("graph","typed-rows")}
        cases.append({"kind": "compute-small-output" if compute else "join-large-output",
                      "rowsPerSource": size, "inputSHA": digest(rows),
                      "sourceSHA": hashlib.sha256(source.encode()).hexdigest(),
                      "observations": observations, "medianSeconds": medians,
                      "rayonSpeedup": {mode:medians[mode]["1"]/medians[mode]["4"] for mode in medians},
                      "transportSpeedup": {str(w):medians["graph"][str(w)]/medians["typed-rows"][str(w)] for w in (1,4)}})
    after = runtime_identity()
    assert before == after
    print(json.dumps({"schema": "ascent.core-c-abi-rayon-measurement.v1",
          "sourceSHA": hashlib.sha256(SOURCE.encode()).hexdigest(),
          "extensionSHA": hashlib.sha256(Path(ascent._core.__file__).read_bytes()).hexdigest(),
          "sourceInventorySHA": digest(before["sourceInputs"]), "sourceInventoryStable": True,
          "cases": cases, "scope": "fixed Core ABI relational workload, not full workflow speedup"}))


if __name__ == "__main__":
    main()
