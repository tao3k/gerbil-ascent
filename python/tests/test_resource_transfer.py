# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Permission failures cannot silently alter native generation publication."""
import errno
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from ascent.build import transfer_resource


class NativePublicationPermission(unittest.TestCase):
    def test_denied_generation_link_does_not_publish_a_copied_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source/module.o1"
            target = Path(directory) / "published/module.o1"
            source.parent.mkdir()
            target.parent.mkdir()
            source.write_bytes(b"original generation")
            target.mkdir()
            # Rust unit coverage separately injects EPERM/EACCES/EIO into the
            # native hard-link operation and requires zero copy fallback.
            with self.assertRaises(OSError): transfer_resource(source, target)
            self.assertTrue(target.is_dir())
            self.assertEqual(list(target.iterdir()), [])
            self.assertEqual(source.read_bytes(), b"original generation")



if __name__ == "__main__":
    unittest.main()
