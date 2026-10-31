"""Run prebuilt hybrid binaries; Python orchestrates, Rust checks every tuple."""
import argparse
from .repository_policy import artifact_path
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import tomllib

SHAPES = [(1, 16, 16), (1, 256, 16), (8, 32, 16), (1, 32, 64), (1, 2048, 16), (8, 256, 16)]
HEADER = "components groups width backend threads sample replace_ns call_ns export_ns wall_ns output_rows".split()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=artifact_path, required=True)
    parser.add_argument("--samples", type=int, default=7)
    args = parser.parse_args()
    root = Path.cwd().resolve()
    binary = args.binary.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, PATH="/usr/bin:/bin", GERBIL_PATH=str(root / ".gerbil"))
    if "GERBIL_HOME" not in env:
        raise SystemExit("explicit installed Scheme syntax-resource root required")
    receipts = []
    source_inputs = {}
    for directory in ["core", "table", "program", "candidate", "applications", "evidence", "interface",
                      "rust/ascent/src", "rust/ascent-scheme/src", "rust/ascent-python/src", "rust/ascent/benches", "rust/ascent-scheme/benches", "workbench/src/ascent_workbench"]:
        for path in (root / directory).rglob("*"):
            if path.is_file() and path.suffix in {".ss", ".rs", ".py"}:
                source_inputs[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
    for name in ["rust/Cargo.toml", "rust/Cargo.lock", "rust/ascent/Cargo.toml", "rust/ascent-scheme/Cargo.toml", "rust/ascent-python/Cargo.toml", "rust/ascent/build.rs", "rust/ascent-scheme/build.rs", "build.ss", "gerbil.pkg"]:
        source_inputs[name] = hashlib.sha256((root/name).read_bytes()).hexdigest()
    manifest = dict(source_inputs=source_inputs, binary=str(binary), binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                    samples=args.samples, shapes=SHAPES, runtime_path=env["PATH"],
                    gerbil_home=env["GERBIL_HOME"], frontend_vm_count=1, vm_owner_threads=1,
                    build_pin=tomllib.loads((root/"rust/Cargo.toml").read_text())["workspace"]["dependencies"]["gerbil-scheme"]["rev"],
                    source_diff_sha256=hashlib.sha256(subprocess.check_output(["git","diff","--binary","HEAD"],cwd=root)).hexdigest(),
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
    drift = [name for name, digest in source_inputs.items()
             if not (root/name).is_file() or hashlib.sha256((root/name).read_bytes()).hexdigest()!=digest]
    (args.output / "source-audit.json").write_text(json.dumps({"drift":drift},indent=2)+"\n")
    if drift:
        raise SystemExit("benchmark source drift; timings diagnostic only")
    if any(r["status"]!=0 or r["samples"]!=args.samples or not r["valid_columns"] for r in receipts):
        raise SystemExit("hybrid failures retained; no incomplete run admitted as success")

if __name__ == "__main__": main()
