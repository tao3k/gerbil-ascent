# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Permission failures cannot silently alter native generation publication."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from ascent.build import PackageManifest


class PublicationPermission(unittest.TestCase):
    def test_denied_generation_link_does_not_publish_a_copied_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source/module.o1"
            target = Path(directory) / "published"
            source.parent.mkdir()
            target.mkdir()
            source.write_bytes(b"original generation")
            manifest = {'schema': 'gerbil-scheme-python.package.v1',
                        'roots': ['source'], 'load_paths': [], 'files': {
                            'source/module.o1': {'sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                                                 'origin': 'fixed-producer/source/module.o1'}}}
            verified = PackageManifest(json.dumps(manifest).encode()).verify(Path(directory))
            # Explicit publication never changes into another transfer mode
            # when the destination has conflicting, unowned contents.
            (target / 'source').write_bytes(b'not-a-directory')
            with self.assertRaises(OSError): verified.copy_to(target)
            self.assertTrue(target.is_dir())
            self.assertEqual((target / 'source').read_bytes(), b'not-a-directory')
            self.assertEqual(source.read_bytes(), b"original generation")



if __name__ == "__main__":
    unittest.main()
