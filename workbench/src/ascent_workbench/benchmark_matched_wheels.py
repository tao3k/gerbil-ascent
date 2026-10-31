"""Installed artifact pairing only; execution and answers stay in the Library."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-python", type=Path, required=True)
    parser.add_argument("--candidate-python", type=Path, required=True)
    parser.add_argument("--workload", type=Path, required=True)
    parser.add_argument("--sandbox", type=Path, required=True)
    args = parser.parse_args()
    paths = {name: getattr(args, name).absolute() for name in
             ("baseline_python", "candidate_python", "workload", "sandbox")}
    assert all(path.is_file() for path in paths.values())
    hashes = {name: hashlib.sha256(path.read_bytes()).hexdigest()
              for name, path in paths.items() if name in ("workload", "sandbox")}
    env = {key: value for key, value in os.environ.items()
           if not key.startswith("GERBIL_") and key != "PYTHONPATH"}
    env["PATH"] = "/usr/bin:/bin"
    started = time.monotonic()
    observations = []
    expected = None
    error = None
    try:
        for pair in range(3):
            order = ("baseline", "candidate") if pair % 2 == 0 else ("candidate", "baseline")
            for label in order:
                remaining = 90 - (time.monotonic() - started)
                if remaining <= 0:
                    raise TimeoutError("whole paired measurement exhausted original 90s cap")
                command = ["/usr/bin/sandbox-exec", "-f", str(paths["sandbox"]),
                           str(paths[label + "_python"]), str(paths["workload"])]
                child = subprocess.run(command, capture_output=True, text=True,
                                       timeout=remaining, env=env, check=False)
                row = {"pair": pair, "artifact": label, "argv": command,
                       "exit": child.returncode, "stderr": child.stderr, "stdout": child.stdout}
                observations.append(row)
                assert child.returncode == 0, child.stderr
                body = json.loads(child.stdout)
                assert body["sourceInventoryStable"]
                signature = [(case["kind"], case["rowsPerSource"], case["inputSHA"],
                              case["sourceSHA"], sorted({run["answerSHA"]
                              for run in case["observations"]})) for case in body["cases"]]
                if expected is None:
                    expected = signature
                assert signature == expected, "complete answer/input mismatch"
                row["measurement"] = body
        assert all(hashlib.sha256(paths[name].read_bytes()).hexdigest() == sha
                   for name, sha in hashes.items())
    except (AssertionError, TimeoutError, subprocess.TimeoutExpired, ValueError) as failure:
        error = str(failure)
    finally:
        print(json.dumps({"schema": "ascent.matched-wheels.v1", "budgetSeconds": 90,
              "seconds": time.monotonic() - started, "inputs": hashes,
              "observations": observations, "completeAnswersMatched": error is None,
              "error": error, "scope": "local paired workload; not full consumer admission"}))
    if error is not None:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
