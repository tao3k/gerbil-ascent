# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Validation reuse must preserve content and process-version admission."""
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from ascent.artifact import ArtifactValidation


class ArtifactValidationTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.library = self.root / 'engine.so'
        self.library.write_bytes(b'library')
        self.resource = self.root / 'syntax/module.o1'
        self.resource.parent.mkdir()
        self.resource.write_bytes(b'original')
        self.receipt_path = self.root / 'engine.so.json'
        self.receipt = {'librarySha256': self.sha(self.library),
                        'syntaxResources': {'module.o1': self.sha(self.resource)}}
        self.publish()
        self.validation = ArtifactValidation()

    @staticmethod
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def publish(self):
        self.receipt_path.write_text(json.dumps(self.receipt))

    def test_repeat_checks_stats_without_reading_unchanged_resource_bytes(self):
        self.validation.read(self.library, self.receipt_path)
        with patch.object(Path, 'read_bytes', side_effect=AssertionError('rehashed')):
            self.assertEqual(self.validation.read(self.library, self.receipt_path), self.receipt)

    def test_same_length_edit_with_restored_mtime_is_rejected(self):
        self.validation.read(self.library, self.receipt_path)
        old = self.resource.stat()
        self.resource.write_bytes(b'modified')
        os.utime(self.resource, ns=(old.st_atime_ns, old.st_mtime_ns))
        with self.assertRaisesRegex(ValueError, 'syntax resource identity drift'):
            self.validation.read(self.library, self.receipt_path)

    def test_valid_new_receipt_cannot_replace_loaded_version(self):
        self.validation.read(self.library, self.receipt_path)
        self.resource.write_bytes(b'modified')
        self.receipt['syntaxResources']['module.o1'] = self.sha(self.resource)
        self.publish()
        with self.assertRaisesRegex(ValueError, 'start a fresh process'):
            self.validation.read(self.library, self.receipt_path)

    def test_removed_receipt_remains_required(self):
        self.validation.read(self.library, self.receipt_path)
        self.receipt_path.unlink()
        self.assertTrue(self.validation.has_receipt(self.receipt_path))
        with self.assertRaises(FileNotFoundError):
            self.validation.read(self.library, self.receipt_path)

    def test_resource_path_escape_is_rejected(self):
        self.receipt['syntaxResources'] = {'../outside': 'unknown'}
        self.publish()
        with self.assertRaisesRegex(ValueError, 'invalid native syntax resource path'):
            self.validation.read(self.library, self.receipt_path)

    def test_api_validates_both_extension_and_bundled_library(self):
        extension = self.root / '_ascent_cffi.so'
        extension.write_bytes(b'extension')
        api = self.root / 'receipt.json'
        api.write_text(json.dumps(dict(self.receipt, library=self.library.name,
                                      extensionSha256=self.sha(extension))))
        self.validation.read(extension, api)
        self.library.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'native library identity drift'):
            self.validation.read(extension, api)
