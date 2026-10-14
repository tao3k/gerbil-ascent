"""Run prebuilt hybrid binaries; Python orchestrates, Rust checks every tuple."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

SHAPES = [(1, 16, 16), (1, 256, 16), (8, 32, 16), (1, 32, 64), (1, 2048, 16), (8, 256, 16)]
HEADER = "components groups width backend threads sample replace_ns call_ns export_ns wall_ns output_rows".split()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=7)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    binary = args.binary.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, PATH="/usr/bin:/bin", GERBIL_PATH=str(root / ".gerbil"))
    if "GERBIL_HOME" not in env:
        raise SystemExit("explicit installed Scheme syntax-resource root required")
    receipts = []
    manifest = dict(binary=str(binary), binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                    samples=args.samples, shapes=SHAPES, runtime_path=env["PATH"],
                    gerbil_home=env["GERBIL_HOME"], frontend_vm_count=1, vm_owner_threads=1,
                    build_pin="0c18941cc6b6b7ff0ef3943abdb2b5fac8e92ccb",
                    scope="native Scheme DSL frontend, native VM or owned finite DAG on Rayon; no multi-VM qualification")
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2)+"\n")
    with (args.output / "samples.tsv").open("w") as output:
        writer = csv.writer(output, delimiter="\t", lineterminator="\n")
        writer.writerow(HEADER)
        for shape in SHAPES:
            for backend, threads in [("vm", 1), *(("rayon", n) for n in [1, 2, 4, 8, 12])]:
                command = [str(binary), *map(str,shape), backend, str(threads), str(args.samples)]
                key = f"k{shape[0]}-g{shape[1]}-w{shape[2]}-{backend}-{threads}"
                started = time.monotonic()
                try:
                    result = subprocess.run(command, cwd=root, env=env, capture_output=True, text=True, timeout=150)
                    stdout, stderr, status = result.stdout, result.stderr, result.returncode
                except subprocess.TimeoutExpired as error:
                    stdout = error.stdout or b""
                    if isinstance(stdout, bytes): stdout = stdout.decode(errors="replace")
                    stderr, status = "watchdog 150s", "timeout"
                (args.output / f"{key}.stdout").write_text(stdout)
                (args.output / f"{key}.stderr").write_text(stderr)
                rows = [line.split("\t") for line in stdout.splitlines() if line]
                valid = all(len(row)==len(HEADER) for row in rows)
                if valid: writer.writerows(rows); output.flush()
                receipts.append(dict(key=key,status=status,samples=len(rows),valid_columns=valid,
                                     process_wall_s=time.monotonic()-started,command=command))
                (args.output / "runs.json").write_text(json.dumps(receipts,indent=2)+"\n")
                print(key, status, len(rows), flush=True)
    if any(r["status"]!=0 or r["samples"]!=args.samples or not r["valid_columns"] for r in receipts):
        raise SystemExit("hybrid failures retained; no incomplete run admitted as success")

if __name__ == "__main__": main()
