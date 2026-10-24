"""Summarize every retained timing; report medians, ranges, and fixed baselines."""
import argparse
from .repository_policy import artifact_path
from collections import defaultdict
import csv
from pathlib import Path
from statistics import median


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("inputs", type=Path, nargs="+")
    parser.add_argument("--output", type=artifact_path, required=True)
    args = parser.parse_args()
    groups = defaultdict(list)
    for path in args.inputs:
        with path.open() as stream:
            for row in csv.DictReader(stream, delimiter="\t"):
                key = tuple(row[n] for n in ("components", "groups", "width", "backend", "workers"))
                groups[key].append(row)
    records = []
    for key, rows in groups.items():
        record = dict(zip(("components", "groups", "width", "backend", "workers"), key))
        record["samples"] = len(rows)
        record["output_rows"] = rows[0]["output_rows"]
        for phase in ("admit", "replace", "solve", "export", "wall"):
            values = [int(row[f"{phase}_ns"]) / 1e6 for row in rows]
            record[f"{phase}_median_ms"] = median(values)
            if phase == "wall":
                record["wall_min_ms"], record["wall_max_ms"] = min(values), max(values)
        if key[3] == "scheme-aot-rayon":
            base = groups[(*key[:3], "scheme-aot-rayon", "1")]
            record["speedup_vs_rayon1"] = median(int(row["wall_ns"]) for row in base) / (record["wall_median_ms"] * 1e6)
            serial = groups[(*key[:3], "scheme-aot-serial", "1")]
            record["speedup_vs_serial"] = median(int(row["wall_ns"]) for row in serial) / (record["wall_median_ms"] * 1e6)
        records.append(record)
    fields = list(records[0]) + ["speedup_vs_rayon1", "speedup_vs_serial"]
    with args.output.open("w") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(records)
    print(f"{sum(len(rows) for rows in groups.values())} samples, {len(records)} configurations -> {args.output}")


if __name__ == "__main__":
    main()
