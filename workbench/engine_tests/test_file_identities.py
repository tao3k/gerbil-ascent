# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Check the installed source inventory against the actual wheel bytes."""
import hashlib
from pathlib import Path
import unittest

from ascent.build import runtime_identity


class FileIdentities(unittest.TestCase):
    def test_complete_installed_source_inventory_matches_actual_bytes(self):
        build = runtime_identity()
        root = Path(build["sourceRoot"])
        sources = build["sourceInputs"]
        self.assertTrue(sources)
        actual = {
            name: hashlib.sha256((root / name).read_bytes()).hexdigest()
            for name in sources
        }
        self.assertEqual(actual, sources)


if __name__ == "__main__":
    unittest.main()
