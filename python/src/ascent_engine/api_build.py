# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Compile CFFI API glue against a prebuilt AOT engine and its actual header.

This is a local extension build, not a portable wheel repair tool. Scheme
compilation and native engine linking remain owned by build.ss/std/make.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

from cffi import FFI
from . import CDEF
from .build import transfer_resource


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(library, header, output, cc):
    library, header, output = library.resolve(), header.resolve(), output.resolve()
    if not library.is_file() or not header.is_file():
        raise ValueError("built engine and matching public header are required")
    system = platform.system()
    if system not in ("Darwin", "Linux"):
        raise ValueError("only the existing POSIX engine platforms are supported")
    compiler = shutil.which(cc)
    if compiler is None:
        raise ValueError("C compiler not found")
    compiler_version = subprocess.check_output([compiler, "--version"], text=True)
    if "clang" in compiler_version.lower() or "gcc" not in compiler_version.lower():
        raise ValueError("this qualification path requires explicit GNU GCC")
    before = {"library": sha(library), "header": sha(header)}
    # A sidecar, when supplied by the producer, must agree. Its absence is not
    # evidence of source/binary correspondence and is recorded below.
    sidecar = library.with_suffix(library.suffix + ".json")
    sidecar_hash = None
    producer = None
    if sidecar.is_file():
        producer = json.loads(sidecar.read_text())
        if producer.get("librarySha256") != before["library"] or producer.get("headerSha256") != before["header"]:
            raise ValueError("producer receipt does not match the library/header")
        sidecar_hash = sha(sidecar)
    output.mkdir(parents=True, exist_ok=False)
    name = "libascent.dylib" if system == "Darwin" else "libascent.so"
    bundled = output / name
    shutil.copyfile(library, bundled)
    syntax_resources={}
    resource_transfers={}
    for relative, asset in (producer or {}).get('syntaxResources', {}).items():
        resource_name=Path(relative)
        if resource_name.is_absolute() or '..' in resource_name.parts:
            raise ValueError('invalid producer syntax resource path')
        source=Path(asset['path'])
        if sha(source)!=asset['sha256']: raise ValueError('producer syntax resource drift')
        target=output/'syntax'/resource_name
        target.parent.mkdir(parents=True,exist_ok=True)
        mode=transfer_resource(source,target)
        resource_transfers[mode]=resource_transfers.get(mode,0)+1
        if sha(source)!=asset['sha256'] or sha(target)!=asset['sha256']:
            raise ValueError('syntax resource changed during API build')
        syntax_resources[str(resource_name)]=asset['sha256']
    if system == "Darwin":
        subprocess.run(["install_name_tool", "-id", "@rpath/" + name, str(bundled)], check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(bundled)], check=True)
    builder = FFI()
    builder.cdef(CDEF)
    # This local builder does not advertise an older wheel deployment target
    # than the host on which the AOT library is being qualified.
    deployment = ["-mmacosx-version-min=" + platform.mac_ver()[0]] if system == "Darwin" else []
    builder.set_source("_ascent_cffi", '#include "ascent.h"',
                       include_dirs=[str(header.parent)], library_dirs=[str(output)],
                       libraries=["ascent"],
                       extra_compile_args=["-Werror=incompatible-pointer-types", *deployment],
                       extra_link_args=["-Wl,-rpath," + ("@loader_path" if system == "Darwin" else "$ORIGIN"), *deployment])
    previous = os.environ.get("CC")
    os.environ["CC"] = compiler
    try:
        extension = Path(builder.compile(tmpdir=str(output), verbose=False))
    finally:
        if previous is None:
            os.environ.pop("CC", None)
        else:
            os.environ["CC"] = previous
    if before != {"library": sha(library), "header": sha(header)} or (
        sidecar_hash is not None and sha(sidecar) != sidecar_hash
    ):
        raise ValueError("producer inputs changed during API compilation")
    for relative, asset in (producer or {}).get('syntaxResources', {}).items():
        if sha(Path(asset['path'])) != asset['sha256'] or sha(output/'syntax'/relative) != asset['sha256']:
            raise ValueError('syntax resource changed before API publication')
    receipt = {"schema": "ascent.cffi-api-build.v1", "backend": "out-of-line-api",
               "producerInputs": before, "producerReceiptSha256": sidecar_hash,
               "producerBuild": producer,
               "syntaxResources": syntax_resources,
               "syntaxResourceTransfers": resource_transfers,
               "compiler": compiler_version.splitlines()[0],
               "localDeploymentTarget": platform.mac_ver()[0] if system == "Darwin" else None,
               "extension": extension.name, "extensionSha256": sha(extension),
               "library": name, "librarySha256": sha(bundled),
               "portableWheelQualified": False}
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--header", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--cc", required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.library, args.header, args.out, args.cc), sort_keys=True))


if __name__ == "__main__":
    main()
