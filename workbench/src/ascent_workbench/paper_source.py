# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Verify local paper input bytes and TSV shape before invoking a truth oracle."""
import argparse
import hashlib
import json
import re
from pathlib import Path


def verify(directory: Path, manifest: dict) -> int:
    total = 0
    names = set()
    if not manifest["files"]:
        raise ValueError("paper source manifest must contain files")
    for source in manifest["files"]:
        name = source["relation"]
        # The manifest binds input identities, not a runtime relation catalog.
        # A single identifier prevents a manifest from selecting arbitrary paths.
        if not isinstance(name, str) or re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", name) is None:
            raise ValueError(f"invalid paper relation identifier: {name}")
        if name in names:
            raise ValueError(f"duplicate paper relation: {name}")
        names.add(name)
        for field, minimum in (("arity", 1), ("rows", 0), ("bytes", 0)):
            value = source[field]
            if type(value) is not int or value < minimum:
                raise ValueError(f"invalid paper source {field}: {name}")
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
