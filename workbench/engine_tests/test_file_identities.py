# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Installed-wheel batch identities retain every SHA without cached admission."""
import hashlib
import json
from pathlib import Path
import tempfile
import time
import unittest

from ascent.build import file_identities, runtime_identity


class FileIdentities(unittest.TestCase):
    def test_complete_installed_source_inventory_matches_actual_bytes(self):
        build = runtime_identity()
        root = Path(build["sourceRoot"])
        paths = [root / name for name in build["sourceInputs"]]
        expected = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
        self.assertEqual(file_identities(paths + paths), expected)
        self.assertEqual(file_identities([]), {})

    def test_matched_source_bytes_three_alternating_pairs(self):
        build = runtime_identity()
        paths = [Path(build["sourceRoot"]) / name for name in build["sourceInputs"]]
        expected = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
        observations = []
        for pair in range(3):
            for mode in (("python", "rust") if pair % 2 == 0 else ("rust", "python")):
                started = time.perf_counter()
                result = (file_identities(paths) if mode == "rust" else
                          {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths})
                seconds = time.perf_counter() - started
                self.assertEqual(result, expected)
                observations.append({"pair": pair, "mode": mode, "seconds": seconds})
        print(json.dumps({"scope": "per-path hashing, not full consumer performance",
                          "sourceInputs": build["sourceInputs"],
                          "distinctPaths": len(expected), "observations": observations}))

    def test_changes_and_aliases_never_reuse_an_old_verdict(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(strict=True)
            path = root / "input"
            path.write_bytes(b"before")
            before = file_identities([path])
            path.write_bytes(b"after!")
            self.assertNotEqual(before, file_identities([path]))
            alias = root / "alias"
            alias.symlink_to(path)
            with self.assertRaises(ValueError):
                file_identities([alias])
            path.unlink()
            with self.assertRaises(ValueError):
                file_identities([path])


if __name__ == "__main__":
    unittest.main()
