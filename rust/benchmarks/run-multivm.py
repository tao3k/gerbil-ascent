"""Diagnostic independent runtime images; every image runs existing ASCENT Actors."""
import argparse
import csv
import json
from pathlib import Path
import shutil
import subprocess
import time

SHAPES = [(1, 16, 16), (1, 256, 16), (8, 32, 16), (1, 32, 64), (1, 2048, 16), (8, 256, 16)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=7)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    build = root / ".cache/ascent/multivm"
    args.output.mkdir(parents=True, exist_ok=True)
    copied_at = time.monotonic_ns()
    images = [build / f"owner-{i}.dylib" for i in range(12)]
    for path in images:
        shutil.copyfile(build / "ascent-vm.dylib", path)
    copy_ns = time.monotonic_ns() - copied_at
    receipts = []
    with (args.output / "samples.tsv").open("w") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow("components groups width backend owners sample wall_ns output_rows".split())
        for shape in SHAPES:
            for owners in [1, 2, 4, 8, 12]:
                key = f"k{shape[0]}-g{shape[1]}-w{shape[2]}-vm{owners}"
                command = [str(build / "vm-runner"), *map(str, shape), str(owners), str(args.samples), *map(str, images[:owners])]
                started = time.monotonic()
                try:
                    result = subprocess.run(command, capture_output=True, text=True, timeout=150)
                    stdout, stderr, status = result.stdout, result.stderr, result.returncode
                except subprocess.TimeoutExpired as error:
                    stdout = (error.stdout or b"").decode() if isinstance(error.stdout, bytes) else error.stdout or ""
                    stderr, status = "watchdog 150s", "timeout"
                (args.output / f"{key}.stdout").write_text(stdout)
                (args.output / f"{key}.stderr").write_text(stderr)
                rows = [line.split("\t") for line in stdout.splitlines() if line]
                valid = all(len(row) == 8 for row in rows)
                if valid:
                    writer.writerows(rows)
                    stream.flush()
                receipts.append(dict(key=key, status=status, samples=len(rows), valid_columns=valid, process_wall_s=time.monotonic()-started, command=command))
                (args.output / "runs.json").write_text(json.dumps(dict(copy_all_images_ns=copy_ns, image_bytes=(build / "ascent-vm.dylib").stat().st_size, runs=receipts), indent=2)+"\n")
                print(key, status, len(rows), flush=True)
    if any(r["status"] != 0 or r["samples"] != args.samples or not r["valid_columns"] for r in receipts):
        raise SystemExit("VM diagnostic failures retained")


if __name__ == "__main__":
    main()
