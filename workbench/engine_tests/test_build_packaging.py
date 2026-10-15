# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import errno
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from ascent.build import build, sha, transfer_resource, prepare


class NativeArtifactPackaging(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.native = self.root / "native"
        self.library = self.native / "bin/libascent"
        self.library.parent.mkdir(parents=True)
        self.library.write_bytes(b"producer-library")
        (self.root / "build.ss").write_text("native-build-spec")
        self.resource = self.native / "lib/syntax~1.scm"
        self.resource.parent.mkdir(parents=True)
        self.resource.write_text("(define native-phase 'compiled-by-gxc)")
        self.receipt = {
            "schema": "ascent.c-abi-build.v1",
            "buildOwner": "build.ss/std/make",
            "librarySha256": sha(self.library),
            "sourceInputs": {"build.ss": sha(self.root / "build.ss")},
            "syntaxResources": {"syntax~1.scm": {
                "path": str(self.resource), "sha256": sha(self.resource)}},
        }
        self.sidecar = self.library.with_name("libascent.json")
        self.publish_receipt()
        self.output = self.root / "package/libascent.so"

    def publish_receipt(self):
        self.sidecar.write_text(json.dumps(self.receipt))

    def test_only_packages_exact_native_outputs_without_a_compiler(self):
        with patch.dict("os.environ", {"PATH": "/unavailable"}), \
                patch("subprocess.Popen", side_effect=AssertionError("compiler launched")):
            build(self.root, self.output, self.native)
        self.assertEqual(self.library.read_bytes(), self.output.read_bytes())
        self.assertEqual(self.resource.read_bytes(),
                         (self.output.parent / "syntax/syntax~1.scm").read_bytes())
        receipt = json.loads(self.output.with_suffix(".so.json").read_text())
        self.assertEqual("build.ss/std/make", receipt["buildOwner"])
        self.assertEqual(sha(self.sidecar), receipt["nativeBuildReceiptSha256"])

    def test_missing_receipt_does_not_attempt_native_build(self):
        self.sidecar.unlink()
        with self.assertRaisesRegex(ValueError, "run gxi build.ss first"):
            build(self.root, self.output, self.native)
        self.assertFalse(self.output.exists())

    def test_compiled_generations_preserve_names_bytes_and_origin(self):
        for generation in (1, 2):
            name = f"syntax~1.o{generation}"
            path = self.resource.with_name(name)
            path.write_bytes(f"actual-linker-name:{name}".encode())
            self.receipt["syntaxResources"][name] = {"path": str(path), "sha256": sha(path)}
        self.receipt["compiledResourceOrigins"] = {"syntax~1.o2": {
            "module": "syntax~1", "path": str(self.resource.with_suffix(".o2")),
            "sha256": sha(self.resource.with_suffix(".o2")), "fallbackSha256": sha(self.resource)}}
        self.publish_receipt()
        build(self.root, self.output, self.native)
        packaged = json.loads(self.output.with_suffix(".so.json").read_text())
        self.assertEqual(self.receipt["compiledResourceOrigins"], packaged["compiledResourceOrigins"])
        for name, asset in self.receipt["syntaxResources"].items():
            target = self.output.parent / "syntax" / name
            self.assertEqual(Path(asset["path"]).read_bytes(), target.read_bytes())
            self.assertEqual(asset["sha256"], packaged["syntaxResources"][name]["sha256"])

    def test_compiled_generation_drift_is_rejected(self):
        path = self.resource.with_suffix(".o1")
        path.write_bytes(b"compiled-generation")
        self.receipt["syntaxResources"][path.name] = {"path": str(path), "sha256": sha(path)}
        self.publish_receipt()
        path.write_bytes(b"changed-generation")
        with self.assertRaisesRegex(ValueError, "resource identity changed"):
            build(self.root, self.output, self.native)
        self.assertFalse(self.output.exists())

    def test_published_generation_survives_native_unlink_and_replacement(self):
        compiled = self.resource.with_suffix(".o1")
        compiled.write_bytes(b"original generation")
        self.receipt["syntaxResources"][compiled.name] = {"path": str(compiled), "sha256": sha(compiled)}
        self.publish_receipt()
        build(self.root, self.output, self.native)
        published = self.output.parent / "syntax" / compiled.name
        self.assertFalse(published.is_symlink())
        self.assertEqual(compiled.stat().st_ino, published.stat().st_ino)
        compiled.unlink()
        compiled.write_bytes(b"next native compilation")
        self.assertEqual(b"original generation", published.read_bytes())
        self.assertNotEqual(compiled.stat().st_ino, published.stat().st_ino)

    def test_cross_volume_generation_copy_remains_independent(self):
        source = self.root / "phase~1.o2"
        directory = self.root / "published"
        directory.mkdir()
        target = directory / source.name
        source.write_bytes(b"compiled generation")
        # The Rust unit test injects CrossesDevices at the actual link syscall.
        # The language binding checks explicit copied-publication ownership.
        self.assertEqual("copied", transfer_resource(source, target, copy=True))
        source.write_bytes(b"changed source")
        self.assertEqual(b"compiled generation", target.read_bytes())

    def test_link_io_failure_does_not_turn_into_a_copy_success(self):
        source = self.root / "phase.o1"
        source.write_bytes(b"compiled generation")
        directory = self.root / "published"
        directory.mkdir()
        target = directory / source.name
        target.mkdir()  # A real failing publication destination, without Python I/O hooks.
        with self.assertRaises(OSError): transfer_resource(source, target)
        self.assertTrue(target.is_dir())
        self.assertEqual(list(target.iterdir()), [])

    def test_generation_cannot_be_renamed_even_with_identical_bytes(self):
        source = self.root / "phase~1.o2"
        source.write_bytes(b"linker symbol contains phase~1.o2")
        with self.assertRaisesRegex(ValueError, "generation filename changed"):
            transfer_resource(source, self.root / "phase~1.o1")
        self.assertFalse((self.root / "phase~1.o1").exists())

    def test_in_place_generation_change_before_publication_is_rejected(self):
        compiled = self.resource.with_suffix(".o1")
        compiled.write_bytes(b"original generation")
        self.receipt["syntaxResources"][compiled.name] = {"path": str(compiled), "sha256": sha(compiled)}
        self.publish_receipt()
        staged = prepare(self.root, self.output, self.native)
        compiled.write_bytes(b"illegal in-place modification")
        with self.assertRaisesRegex(ValueError, "resource changed before publication"):
            staged.publish()
        self.assertFalse(self.output.exists())

    def test_repackaging_removes_unrecorded_contiguous_generations(self):
        build(self.root, self.output, self.native)
        syntax = self.output.parent / "syntax"
        for generation in (1, 2, 3):
            (syntax / f"syntax~1.o{generation}").write_bytes(b"old compiled module")
        compiled = self.resource.with_suffix(".o1")
        compiled.write_bytes(b"current compiled module")
        self.receipt["syntaxResources"][compiled.name] = {"path": str(compiled), "sha256": sha(compiled)}
        self.publish_receipt()
        build(self.root, self.output, self.native)
        self.assertEqual({"syntax~1.scm", "syntax~1.o1"}, {p.name for p in syntax.iterdir()})
        self.assertEqual(compiled.read_bytes(), (syntax / compiled.name).read_bytes())

    def test_failed_repackaging_preserves_previous_resources_and_library(self):
        build(self.root, self.output, self.native)
        syntax = self.output.parent / "syntax"
        previous = {p.name: p.read_bytes() for p in syntax.iterdir()}
        library = self.output.read_bytes()
        self.resource.write_bytes(b"new valid first resource")
        self.receipt["syntaxResources"][self.resource.name]["sha256"] = sha(self.resource)
        later = self.resource.with_name("later.scm")
        later.write_bytes(b"original later resource")
        self.receipt["syntaxResources"][later.name] = {"path": str(later), "sha256": sha(later)}
        self.publish_receipt()
        later.write_bytes(b"changed later resource")
        with self.assertRaisesRegex(ValueError, "resource identity changed"):
            build(self.root, self.output, self.native)
        self.assertEqual(previous, {p.name: p.read_bytes() for p in syntax.iterdir()})
        self.assertEqual(library, self.output.read_bytes())

    def test_stale_source_is_rejected_without_timestamp_inference(self):
        (self.root / "build.ss").write_text("changed-build-spec")
        with self.assertRaisesRegex(ValueError, "source identity changed"):
            build(self.root, self.output, self.native)
        self.assertFalse(self.output.exists())

    def test_resource_drift_is_rejected(self):
        self.resource.write_text("changed-phase")
        with self.assertRaisesRegex(ValueError, "resource identity changed"):
            build(self.root, self.output, self.native)
        self.assertFalse(self.output.exists())

    def test_source_and_resource_paths_cannot_escape_package_roots(self):
        self.receipt["sourceInputs"] = {"../build.ss": "invalid"}
        self.publish_receipt()
        with self.assertRaisesRegex(ValueError, "source input path"):
            build(self.root, self.output, self.native)
        self.receipt["sourceInputs"] = {"build.ss": sha(self.root / "build.ss")}
        self.receipt["syntaxResources"]["../escape.scm"] = self.receipt["syntaxResources"].pop("syntax~1.scm")
        self.publish_receipt()
        with self.assertRaisesRegex(ValueError, "resource path"):
            build(self.root, self.output, self.native)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
