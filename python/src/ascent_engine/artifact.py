# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Process-local artifact validation; changed files always require new hashes."""
import hashlib
import json
from pathlib import Path


class ArtifactValidation:
    def __init__(self):
        self._hashes = {}
        self._receipts = {}

    def has_receipt(self, path):
        return Path(path) in self._receipts

    @staticmethod
    def identity(path):
        info = path.stat()
        return (info.st_dev, info.st_ino, info.st_size,
                info.st_mtime_ns, info.st_ctime_ns)

    def digest(self, path):
        path = Path(path)
        before = self.identity(path)
        cached = self._hashes.get(path)
        if cached is not None and cached[0] == before:
            return cached[1]
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if self.identity(path) != before:
            raise ValueError('artifact changed during validation')
        self._hashes[path] = (before, digest)
        return digest

    def read(self, library, receipt_path):
        library, receipt_path = Path(library), Path(receipt_path)
        before = self.identity(receipt_path)
        receipt = json.loads(receipt_path.read_text())
        if self.identity(receipt_path) != before:
            raise ValueError('artifact receipt changed during validation')
        admitted = (receipt.get('librarySha256'), receipt.get('extensionSha256'),
                    {key: value['sha256'] if isinstance(value, dict) else value
                     for key, value in receipt.get('syntaxResources', {}).items()})
        if receipt_path in self._receipts and self._receipts[receipt_path] != admitted:
            raise ValueError('artifact version changed; start a fresh process')
        if receipt_path.name == 'receipt.json':
            name = Path(receipt['library'])
            if name.is_absolute() or len(name.parts) != 1:
                raise ValueError('invalid native library path')
            if (self.digest(library) != receipt.get('extensionSha256')
                    or self.digest(receipt_path.parent / name) != receipt.get('librarySha256')):
                raise ValueError('native library identity drift')
        else:
            if self.digest(library) != receipt.get('librarySha256'):
                raise ValueError('native library identity drift')
        syntax = receipt_path.parent / 'syntax'
        for relative, expected in receipt.get('syntaxResources', {}).items():
            name = Path(relative)
            if name.is_absolute() or '..' in name.parts:
                raise ValueError('invalid native syntax resource path')
            expected = expected['sha256'] if isinstance(expected, dict) else expected
            if self.digest(syntax / name) != expected:
                raise ValueError('native syntax resource identity drift')
        if self.identity(receipt_path) != before:
            raise ValueError('artifact receipt changed during validation')
        self._receipts[receipt_path] = admitted
        return receipt
