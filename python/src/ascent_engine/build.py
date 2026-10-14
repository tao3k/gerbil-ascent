# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Package the C ABI artifact already built by build.ss/std/make.

This module has no Scheme compiler, dependency graph, phase discovery,
currentness policy, or compilation scheduler.
"""
import argparse
import errno
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import tempfile


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def transfer_resource(source, target):
    """Retain native append-only generations; copy mutable metadata.

    A hard link is a regular, self-contained file, not a loader path alias.
    Native compilation creates a new .oN or unlinks an invalidated generation;
    it must never overwrite a published generation in place. Identity checks
    remain mandatory, including when linking is unavailable across volumes.
    A permission denial must not silently change the publication mode.
    """
    if re.fullmatch(r"\.o[1-9][0-9]*", source.suffix):
        if source.name != target.name:
            raise ValueError("compiled generation filename changed")
        try:
            os.link(source.resolve(strict=True), target)
            return "linked-generation"
        except OSError as error:
            if error.errno == errno.EPERM:
                raise PermissionError(error.errno,
                    "compiled generation publication requires permitted hard-link access", str(target)) from error
            if error.errno not in (errno.EXDEV, errno.ENOTSUP, errno.EMLINK, errno.ENOSYS):
                raise
    shutil.copyfile(source, target)
    return "copied"


def verify_inputs(root, receipt):
    for relative, expected in receipt["sourceInputs"].items():
        name = Path(relative)
        if name.is_absolute() or ".." in name.parts:
            raise ValueError("invalid native source input path")
        if sha(root / name) != expected:
            raise ValueError("native build source identity changed: " + relative)


def build(root, output, build_dir=None):
    root, output = root.resolve(), output.resolve()
    build_dir = Path(build_dir or os.environ.get("GERBIL_PATH", root / ".gerbil")).resolve()
    library = build_dir / "bin/libascent"
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
    transfers = {}
    syntax = output.parent / "syntax"
    # Reusing a package directory must not retain unrecorded .oN generations:
    # the upstream loader could otherwise select old code beyond our prefix.
    with tempfile.TemporaryDirectory(prefix=".ascent-package-", dir=output.parent) as temporary:
        staged = Path(temporary) / "syntax"
        staged.mkdir()
        for relative, asset in receipt["syntaxResources"].items():
            name = Path(relative)
            if name.is_absolute() or ".." in name.parts:
                raise ValueError("invalid native resource path")
            source = Path(asset["path"])
            if sha(source) != asset["sha256"]:
                raise ValueError("native resource identity changed: " + relative)
            target = staged / name
            target.parent.mkdir(parents=True, exist_ok=True)
            mode = transfer_resource(source, target)
            transfers[mode] = transfers.get(mode, 0) + 1
            if sha(source) != asset["sha256"] or sha(target) != asset["sha256"]:
                raise ValueError("native resource changed during packaging")
            resources[relative] = {"path": str(syntax / name), "sha256": asset["sha256"]}
        candidate = Path(temporary) / output.name
        shutil.copyfile(library, candidate)
        verify_inputs(root, receipt)
        for relative, asset in receipt["syntaxResources"].items():
            if sha(Path(asset["path"])) != asset["sha256"] or sha(staged / relative) != asset["sha256"]:
                raise ValueError("native resource changed before publication")
        if sha(sidecar) != before or sha(library) != receipt["librarySha256"] or sha(candidate) != receipt["librarySha256"]:
            raise ValueError("native artifact changed during packaging")
        previous = Path(temporary) / "previous-syntax"
        if syntax.exists():
            syntax.replace(previous)
        try:
            staged.replace(syntax)
            candidate.replace(output)
        except BaseException:
            if syntax.exists():
                shutil.rmtree(syntax)
            if previous.exists():
                previous.replace(syntax)
            raise
    receipt = dict(receipt, syntaxResources=resources, packagingOwner="ascent_engine.build",
                   nativeBuildReceiptSha256=before, syntaxResourceTransfers=transfers)
    output.with_suffix(output.suffix + ".json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("ASCENT-C-ABI-PACKAGE-OK " + str(output), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--build-dir", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    build(args.root, args.output, args.build_dir)


if __name__ == "__main__":
    main()
