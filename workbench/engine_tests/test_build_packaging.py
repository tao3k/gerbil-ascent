# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Shared gerbil-scheme-rust publication types, without downstream compilation."""
import copy
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from ascent.build import PackageManifest


class NativeArtifactPackaging(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.native = self.root / 'producer'
        self.library = self.native / 'assets/libascent.so'
        self.library.parent.mkdir(parents=True)
        self.library.write_bytes(b'fixed-core-library')
        self.resource = self.native / 'assets/algorithm-source.ss'
        self.resource.write_bytes(b'fixed-algorithm-source')
        self.output = self.root / 'package'
        self.receipt = {'schema': 'gerbil-scheme-python.package.v1',
                        'roots': ['assets'], 'load_paths': [],
                        'files': {}}
        self.record(self.library)
        self.record(self.resource)

    def record(self, path):
        name = str(path.relative_to(self.native))
        self.receipt['files'][name] = {
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'origin': 'fixed-producer/' + name}

    def manifest(self):
        return PackageManifest(json.dumps(self.receipt).encode())

    def prepare(self):
        return self.manifest().verify(self.native)

    def snapshot(self, root):
        return {str(p.relative_to(root)): p.read_bytes()
                for p in root.rglob('*') if p.is_file()}

    def test_only_packages_exact_native_outputs_without_a_compiler(self):
        with patch.dict(os.environ, PATH=''), \
                patch('subprocess.Popen', side_effect=AssertionError('compiler launched')):
            actual = self.prepare().publish_to(self.output)
            actual.reverify()
        self.assertEqual(actual.root, self.output.resolve())
        for name, item in self.receipt['files'].items():
            self.assertEqual(hashlib.sha256((self.output / name).read_bytes()).hexdigest(), item['sha256'])

    def test_missing_receipt_does_not_attempt_native_build(self):
        with self.assertRaises(OSError):
            PackageManifest(b'{}')
        self.assertFalse(self.output.exists())

    def test_compiled_generations_preserve_names_bytes_and_origin(self):
        for suffix in ('o1', 'o2'):
            path = self.native / f'assets/algorithm~1.{suffix}'
            path.write_bytes(f'actual-linker-name:{path.name}'.encode())
            self.record(path)
        self.prepare().publish_to(self.output)
        for name in self.receipt['files']:
            self.assertEqual((self.native / name).read_bytes(), (self.output / name).read_bytes())

    def test_compiled_generation_drift_is_rejected(self):
        path = self.native / 'assets/algorithm~1.o1'
        path.write_bytes(b'original-generation')
        self.record(path)
        path.write_bytes(b'changed-generation')
        with self.assertRaises(OSError):
            self.prepare().publish_to(self.output)
        self.assertFalse(self.output.exists())

    def test_published_generation_survives_native_unlink_and_replacement(self):
        self.prepare().publish_to(self.output)
        published = self.output / 'assets/libascent.so'
        before = published.read_bytes()
        self.library.unlink()
        self.library.write_bytes(b'next-compilation')
        self.assertEqual(published.read_bytes(), before)
        self.assertNotEqual(self.library.stat().st_ino, published.stat().st_ino)

    def test_cross_volume_generation_copy_remains_independent(self):
        copied = self.prepare().copy_to(self.output)
        self.library.write_bytes(b'changed-producer')
        copied.reverify()
        self.assertEqual((self.output / 'assets/libascent.so').read_bytes(), b'fixed-core-library')

    def test_link_io_failure_does_not_turn_into_a_copy_success(self):
        self.output.mkdir()
        (self.output / 'assets').write_bytes(b'not-a-directory')
        with self.assertRaises(OSError):
            self.prepare().copy_to(self.output)
        self.assertEqual((self.output / 'assets').read_bytes(), b'not-a-directory')

    def test_generation_cannot_be_renamed_even_with_identical_bytes(self):
        self.prepare().publish_to(self.output)
        target = self.output / 'assets/libascent.so'
        target.rename(target.with_name('renamed.so'))
        with self.assertRaises(OSError):
            self.manifest().verify(self.output)

    def test_in_place_generation_change_before_publication_is_rejected(self):
        staged = self.prepare()
        self.library.write_bytes(b'illegal-in-place-mutation')
        with self.assertRaises(OSError):
            staged.publish_to(self.output)
        self.assertFalse(self.output.exists())

    def test_repackaging_removes_unrecorded_contiguous_generations(self):
        obsolete = self.native / 'assets/obsolete.o1'
        obsolete.write_bytes(b'old-generation')
        self.record(obsolete)
        self.prepare().publish_to(self.output)
        obsolete.unlink()
        del self.receipt['files']['assets/obsolete.o1']
        current = self.native / 'assets/current.o2'
        current.write_bytes(b'current-generation')
        self.record(current)
        self.prepare().publish_to(self.output)
        self.assertFalse((self.output / 'assets/obsolete.o1').exists())
        self.assertEqual((self.output / 'assets/current.o2').read_bytes(), current.read_bytes())

    def test_failed_repackaging_preserves_previous_resources_and_library(self):
        self.prepare().publish_to(self.output)
        before = self.snapshot(self.output)
        self.library.write_bytes(b'new-valid-library')
        self.record(self.library)
        self.resource.write_bytes(b'unrecorded-source-change')
        with self.assertRaises(OSError):
            self.prepare().publish_to(self.output)
        self.assertEqual(self.snapshot(self.output), before)

    def test_stale_source_is_rejected_without_timestamp_inference(self):
        stamp = self.resource.stat()
        self.resource.write_bytes(b'changed-source-with-old-stamp')
        os.utime(self.resource, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
        with self.assertRaises(OSError):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_resource_drift_is_rejected(self):
        self.library.write_bytes(b'changed-library')
        with self.assertRaises(OSError):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_source_and_resource_paths_cannot_escape_package_roots(self):
        for name in ('../escape.so', '/absolute.so', 'assets/../escape.so'):
            altered = copy.deepcopy(self.receipt)
            altered['files'][name] = altered['files'].pop('assets/libascent.so')
            with self.assertRaises(OSError):
                PackageManifest(json.dumps(altered).encode())
        outside = self.root / 'outside.so'
        outside.write_bytes(b'fixed-core-library')
        self.library.unlink()
        self.library.symlink_to(outside)
        with self.assertRaises(OSError):
            self.prepare()


if __name__ == '__main__': unittest.main()
