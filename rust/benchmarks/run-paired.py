"""Interleave frozen pre-change and current binaries without timing process startup."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import subprocess

SHAPES = [(1, 16, 16), (1, 256, 16), (8, 32, 16), (1, 32, 64), (1, 2048, 16), (8, 256, 16)]
FIELDS = "components groups width backend workers sample admit_ns replace_ns solve_ns export_ns wall_ns output_rows cpu_s process_real_s allocated_bytes".split()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = {name: dict(path=str(path), sha256=hashlib.sha256(path.read_bytes()).hexdigest()) for name, path in [("before", args.before), ("after", args.after)]}
    receipts = []
    with (args.output / "samples.tsv").open("w") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(["version", *FIELDS])
        for shape in SHAPES:
            for workers in [0, 1, 2, 4, 8, 12]:
                for sample in range(7):
                    versions = ["before", "after"] if sample % 2 == 0 else ["after", "before"]
                    for version in versions:
                        command = [manifest[version]["path"], *map(str, shape), str(workers), "1"]
                        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
                        lines = [line.split("\t") for line in result.stdout.splitlines() if line]
                        valid = result.returncode == 0 and len(lines) == 1 and len(lines[0]) == len(FIELDS)
                        receipts.append(dict(shape=shape, workers=workers, sample=sample, version=version, status=result.returncode, valid=valid, stderr=result.stderr))
                        if valid:
                            lines[0][5] = str(sample)
                            writer.writerow([version, *lines[0]])
                            stream.flush()
                        (args.output / "runs.json").write_text(json.dumps(dict(binaries=manifest, runs=receipts), indent=2)+"\n")
                        if not valid:
                            raise SystemExit(f"retained failed paired run: {receipts[-1]}")
                print(shape, workers, "7 checked pairs", flush=True)


if __name__ == "__main__":
    main()
