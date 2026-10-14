"""Run prebuilt benchmark programs sequentially; retain samples and failures."""
import argparse
import csv
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
HEADER = "components groups width backend workers sample admit_ns replace_ns solve_ns export_ns wall_ns output_rows cpu_s process_real_s allocated_bytes".split()
SHAPES = [(1, 16, 16), (1, 256, 16), (8, 32, 16), (1, 32, 64)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--large", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scheme", type=Path, required=True)
    parser.add_argument("--rust", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    receipts = []
    env = dict(os.environ, GERBIL_PATH=str(ROOT / ".gerbil"))
    with (args.output / "samples.tsv").open("w") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(HEADER)
        for shape in ([(1, 2048, 16), (8, 256, 16)] if args.large else SHAPES):
            configurations = [("scheme", str(n)) for n in [1, 2, 4, 8, 12]]
            configurations += [("rust", str(n)) for n in [0, 1, 2, 4, 8, 12]] + [("rust", "oracle")]
            for runtime, workers in configurations:
                command = [str(args.scheme if runtime == "scheme" else args.rust)]
                if runtime == "scheme":
                    command += ["-:max-heap=2G,debug=q"]
                command += [*map(str, shape), workers, str(args.samples)]
                key = f"k{shape[0]}-g{shape[1]}-w{shape[2]}-{runtime}-{workers}"
                started = time.monotonic()
                try:
                    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=150)
                    stdout, stderr, status = result.stdout, result.stderr, result.returncode
                except subprocess.TimeoutExpired as error:
                    stdout = (error.stdout or b"").decode() if isinstance(error.stdout, bytes) else error.stdout or ""
                    stderr = "process timeout 150s"
                    status = "timeout"
                (args.output / f"{key}.stdout").write_text(stdout)
                (args.output / f"{key}.stderr").write_text(stderr)
                rows = [line.split("\t") for line in stdout.splitlines() if line and not line.startswith("#")]
                valid = all(len(row) == len(HEADER) for row in rows)
                if valid:
                    writer.writerows(rows)
                    stream.flush()
                receipt = dict(key=key, command=command, status=status, samples=len(rows), valid_columns=valid, process_wall_s=time.monotonic() - started)
                receipts.append(receipt)
                (args.output / "runs.json").write_text(json.dumps(receipts, indent=2) + "\n")
                print(json.dumps(receipt), flush=True)
    if any(r["status"] != 0 or r["samples"] != args.samples or not r["valid_columns"] for r in receipts):
        raise SystemExit("Some runs failed; retained all outputs and partial samples")


if __name__ == "__main__":
    main()
