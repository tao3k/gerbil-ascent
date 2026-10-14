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
            denial = PermissionError(errno.EPERM, "not permitted")
            with patch("ascent.build.os.link", side_effect=denial), \
                 patch("ascent.build.shutil.copyfile") as copy:
                with self.assertRaisesRegex(PermissionError, "hard-link access") as observed:
                    transfer_resource(source, target)
                self.assertEqual(observed.exception.errno, errno.EPERM)
                self.assertIs(observed.exception.__cause__, denial)
                copy.assert_not_called()
            self.assertFalse(target.exists())
            self.assertEqual(source.read_bytes(), b"original generation")


if __name__ == "__main__":
    unittest.main()
