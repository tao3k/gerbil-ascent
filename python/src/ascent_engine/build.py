# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Package the C ABI artifact already built by build.ss/std/make.

This module has no Scheme compiler, dependency graph, phase discovery,
currentness policy, or compilation scheduler.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_inputs(root, receipt):
    for relative, expected in receipt["sourceInputs"].items():
        name = Path(relative)
        if name.is_absolute() or ".." in name.parts:
            raise ValueError("invalid native source input path")
        if sha(root / name) != expected:
            raise ValueError("native build source identity changed: " + relative)


def build(root, output, native_dir=None):
    root, output = root.resolve(), output.resolve()
    native_dir = Path(native_dir or os.environ.get("GERBIL_PATH", root / ".gerbil")).resolve()
    library = native_dir / "bin/libascent"
    sidecar = library.with_name(library.name + ".json")
    if not library.is_file() or not sidecar.is_file():
        raise ValueError("run gxi build.ss first; a successful native build receipt is required")
    receipt = json.loads(sidecar.read_text())
    if (receipt.get("schema") != "ascent.c-abi-build.v1"
            or receipt.get("buildOwner") != "build.ss/std/make"
            or sha(library) != receipt.get("librarySha256")):
        raise ValueError("native build receipt does not match its artifact")
    verify_inputs(root, receipt)
    before = sha(sidecar)
    output.parent.mkdir(parents=True, exist_ok=True)
    resources = {}
    for relative, asset in receipt["syntaxResources"].items():
        name = Path(relative)
        if name.is_absolute() or ".." in name.parts:
            raise ValueError("invalid native resource path")
        source = Path(asset["path"])
        if sha(source) != asset["sha256"]:
            raise ValueError("native resource identity changed: " + relative)
        target = output.parent / "syntax" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        if sha(source) != asset["sha256"] or sha(target) != asset["sha256"]:
            raise ValueError("native resource changed during packaging")
        resources[relative] = {"path": str(target), "sha256": asset["sha256"]}
    candidate = output.with_name(output.name + ".pending")
    shutil.copyfile(library, candidate)
    verify_inputs(root, receipt)
    if sha(sidecar) != before or sha(library) != receipt["librarySha256"] or sha(candidate) != receipt["librarySha256"]:
        raise ValueError("native artifact changed during packaging")
    candidate.replace(output)
    receipt = dict(receipt, syntaxResources=resources, packagingOwner="ascent_engine.build",
                   nativeBuildReceiptSha256=before)
    output.with_suffix(output.suffix + ".json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("ASCENT-C-ABI-PACKAGE-OK " + str(output), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--native-dir", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    build(args.root, args.output, args.native_dir)


if __name__ == "__main__":
    main()
