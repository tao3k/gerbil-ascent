# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from ascent_engine.build import build, sha


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
