# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Shared package owners retain complete per-path content identity."""
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from ascent.build import PackageManifest


class ArtifactValidationTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.assets = self.root / 'assets'
        self.assets.mkdir()
        self.library = self.assets / 'core.so'
        self.library.write_bytes(b'library')
        self.resource = self.assets / 'algorithm.ss'
        self.resource.write_bytes(b'original')
        self.receipt_path = self.root / '.gerbil-scheme-python-package.json'
        self.receipt = {'schema': 'gerbil-scheme-python.package.v1',
                        'roots': ['assets'], 'load_paths': [],
                        'files': {}}
        self.record(self.library)
        self.record(self.resource)
        self.publish()

    @staticmethod
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def record(self, path):
        name = str(path.relative_to(self.root))
        self.receipt['files'][name] = {'sha256': self.sha(path), 'origin': 'fixed-producer/' + name}

    def publish(self):
        self.receipt_path.write_text(json.dumps(self.receipt))

    def verify(self):
        return PackageManifest(self.receipt_path.read_bytes()).verify(self.root)

    def test_repeat_checks_stats_without_reading_unchanged_resource_bytes(self):
        verified = self.verify()
        # Full SHA checks belong to the Rust owner, not Python Path IO or a
        # stat-only cache. This assertion makes no no-rehash performance claim.
        with patch.object(Path, 'read_bytes', side_effect=AssertionError('Python rehashed')):
            again = verified.reverify()
        self.assertEqual(again.root, verified.root)

    def test_same_length_edit_with_restored_mtime_is_rejected(self):
        verified = self.verify()
        old = self.resource.stat()
        self.resource.write_bytes(b'modified')
        os.utime(self.resource, ns=(old.st_atime_ns, old.st_mtime_ns))
        with self.assertRaises(OSError):
            verified.reverify()

    def test_valid_new_receipt_cannot_replace_loaded_version(self):
        verified = self.verify()
        self.resource.write_bytes(b'modified')
        self.record(self.resource)
        self.publish()
        with self.assertRaises(OSError):
            verified.reverify()
        # Explicit verification of new bytes is a new owner, never mutation of
        # the retained old owner or authority to replace a loaded binary.
        fresh = self.verify()
        fresh.reverify()
        with self.assertRaises(OSError):
            verified.reverify()

    def test_removed_receipt_remains_required(self):
        verified = self.verify()
        self.receipt_path.unlink()
        with self.assertRaises(FileNotFoundError):
            self.verify()
        # The retained Rust owner already holds an immutable manifest. Removing
        # its transport file cannot replace that identity or permit byte drift.
        verified.reverify()
        self.resource.write_bytes(b'modified')
        with self.assertRaises(OSError): verified.reverify()

    def test_resource_path_escape_is_rejected(self):
        self.receipt['files']['../outside'] = {'sha256': '0' * 64, 'origin': 'fixed-producer/outside'}
        self.publish()
        with self.assertRaises(OSError):
            self.verify()

    def test_api_validates_both_extension_and_bundled_library(self):
        extension = self.assets / '_core.so'
        extension.write_bytes(b'extension')
        self.record(extension)
        self.publish()
        verified = self.verify()
        self.library.write_bytes(b'changed')
        with self.assertRaises(OSError):
            verified.reverify()
