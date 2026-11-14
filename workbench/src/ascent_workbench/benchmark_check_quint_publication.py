"""Check completed model observations through the installed Core C ABI.

This compares completed finite observations, not Rust execution traces or a
memory-model refinement. Python transports rows and asserts full output equality;
it does not implement the evaluator or derive expected facts.
"""
import argparse
from .repository_policy import artifact_path
from collections import Counter
import json
from pathlib import Path
import ascent

SOURCE = """(ascent
  (relation input ((relation integer?) (value integer?)))
  (relation out0 ((value integer?)))
  (relation out1 ((value integer?)))
  ((out0 value) <-- (input 0 value))
  ((out1 value) <-- (input 1 value)))"""


def rows(field):
    return [[int(cell["#bigint"]) for cell in row["#tup"]] for row in field["#set"]]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("traces", type=Path)
    parser.add_argument("--output", type=artifact_path, required=True)
    args = parser.parse_args()
    receipts, phases, unique = [], Counter(), set()
    for path in sorted(args.traces.glob("*.itf.json")):
        trace = json.loads(path.read_text())
        terminal = trace["states"][-1][trace["vars"][0]]
        phases[terminal["phase"]] += 1
        if terminal["phase"] != "complete":
            continue
        inputs, snapshot = rows(terminal["offered"]), rows(terminal["snapshot"])
        expected = {"input": inputs, **{f"out{head}": [[cell] for relation, cell in snapshot if relation == head] for head in [0, 1]}}
        samples = []
        for workers in [1, 2, 4, 8, 12]:
            with ascent.Engine(backend="rust", workers=workers) as engine:
                with engine.open_sources(SOURCE) as session:
                    if not session.run()['complete']:
                        raise AssertionError('Initial source admission incomplete')
                    session.replace({"input": inputs})
                    result = session.run(queries=list(expected))
                    if (not result['complete'] or
                            {name: sorted(map(tuple, values)) for name, values in result['relations'].items()} !=
                            {name: sorted(map(tuple, values)) for name, values in expected.items()}):
                        raise AssertionError(f"Complete output mismatch: {path.name}, workers={workers}")
                    samples.append({'workers': workers,
                                    'facts': sum(map(len, result['relations'].values()))})
        receipts.append({"trace": path.name, "workers": [s['workers'] for s in samples], "facts": [s['facts'] for s in samples]})
        unique.add(tuple(sorted(map(tuple, snapshot))))
    if not receipts:
        raise SystemExit("No completed observations; correspondence not qualified")
    args.output.write_text(json.dumps({"phases": dict(phases), "completed_observations": len(receipts), "distinct_completed_results": len(unique), "checked_runs": 5 * len(receipts), "runs": receipts, "scope": "completed finite output correspondence; not Rust trace refinement or a performance comparison"}, indent=2) + "\n")
    print(f"RUST-PYO3-MODEL-OUTPUT-OK observations={len(receipts)} distinct={len(unique)} checked_runs={5*len(receipts)}")


if __name__ == "__main__":
    main()
