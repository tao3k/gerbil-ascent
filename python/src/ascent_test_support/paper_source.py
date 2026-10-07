# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Verify local paper input bytes and TSV shape before invoking a truth oracle."""
import argparse
import hashlib
import json
from pathlib import Path


def verify(directory: Path, manifest: dict) -> int:
    total = 0
    for source in manifest["files"]:
        name = source["relation"]
        if name not in ("alloc", "assign", "load", "store"):
            raise ValueError(f"unsupported paper relation: {name}")
        data = (directory / f"{name}.facts").read_bytes()
        blob = b"blob " + str(len(data)).encode() + b"\0" + data
        if (len(data) != source["bytes"]
                or hashlib.sha256(data).hexdigest() != source["sha256"]
                or hashlib.sha1(blob).hexdigest() != source["git_blob"]):
            raise ValueError(f"paper source identity mismatch: {name}")
        rows = data.decode("utf-8").splitlines()
        if len(rows) != source["rows"]:
            raise ValueError(f"paper source row count mismatch: {name}")
        for ordinal, row in enumerate(rows, 1):
            if len(row.split("\t")) != source["arity"]:
                raise ValueError(f"paper source arity mismatch: {name}:{ordinal}")
        total += len(rows)
        print(f"PAPER-SOURCE-OK name={name} rows={len(rows)}", flush=True)
    return total


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    count = verify(args.directory, json.loads(args.manifest.read_text()))
    print(f"PAPER-SOURCE-COMPLETE rows={count}", flush=True)


if __name__ == "__main__":
    main()
