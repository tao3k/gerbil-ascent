# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Byte identity and shape rejection controls; semantic assertions live in Rust."""
import contextlib
import hashlib
import io
from pathlib import Path
import tempfile
import unittest

from ascent_test_support.paper_source import verify


class PaperSource(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.data = b"left\tright\n"
        (self.directory / "alloc.facts").write_bytes(self.data)
        self.manifest = {"files": [{
            "relation": "alloc", "arity": 2, "rows": 1,
            "bytes": len(self.data), "sha256": hashlib.sha256(self.data).hexdigest(),
            "git_blob": hashlib.sha1(b"blob 11\0" + self.data).hexdigest(),
        }]}

    def check_source(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return verify(self.directory, self.manifest)

    def test_exact_bytes(self):
        self.assertEqual(self.check_source(), 1)

    def test_same_length_substitution_is_rejected(self):
        (self.directory / "alloc.facts").write_bytes(b"LEFT\tright\n")
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            self.check_source()

    def test_blob_identity_is_independently_checked(self):
        self.manifest["files"][0]["git_blob"] = "0" * 40
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            self.check_source()

    def test_shape_mismatch_is_rejected(self):
        for key, value, error in [("rows", 2, "row count"), ("arity", 3, "arity")]:
            with self.subTest(key=key):
                source = self.manifest["files"][0]
                previous = source[key]
                source[key] = value
                with self.assertRaisesRegex(ValueError, error):
                    self.check_source()
                source[key] = previous


if __name__ == "__main__":
    unittest.main()
