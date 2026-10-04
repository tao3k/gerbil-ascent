# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Artifact publication failure controls; no Scheme semantic assertions."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


class ArtifactPublication(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'tools').mkdir()
        (self.root / 't/harness').mkdir(parents=True)
        shutil.copyfile(Path(__file__).with_name('dsl-closure-artifact.py'),
                        self.root / 'tools/dsl-closure-artifact.py')
        for name in ('justfile', 't/harness/watch_output.py', 'fixture.ss'):
            (self.root / name).write_text('fixture bytes\n')
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        self.cache = self.root / '.cache/ascent/native-library'
        self.cache.mkdir(parents=True)
        (self.cache / 'dsl-closure').write_bytes(b'fixture executable bytes')
        self.env = {**os.environ, 'ASCENT_DSL_BUILD_TOKEN': 'test-owner',
                    'ASCENT_DSL_BUILD_STARTED': str(time.monotonic())}

    def call(self, mode, success=True, env=None):
        result = subprocess.run(['python3', 'tools/dsl-closure-artifact.py', mode],
                                cwd=self.root, env=env or self.env,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)

    def stage(self):
        self.call('freeze')
        self.call('bind')

    def test_staged_failed_compilation_is_not_accepted(self):
        self.stage()
        self.call('check', False)

    def test_completed_publication_is_accepted(self):
        self.stage()
        self.call('finalize')
        self.call('check')

    def test_other_run_cannot_publish(self):
        self.stage()
        self.call('finalize', False, {**self.env, 'ASCENT_DSL_BUILD_TOKEN': 'other-owner'})
        self.call('check', False)

    def test_expired_build_cannot_stage(self):
        self.stage()
        import json
        path = self.cache / 'dsl-closure-run.json'
        run = json.loads(path.read_text())
        run['started'] = time.monotonic() - 181
        path.write_text(json.dumps(run))
        self.call('bind', False)
        self.call('check', False)

    def test_changed_source_cannot_publish(self):
        self.stage()
        (self.root / 'fixture.ss').write_text('changed source\n')
        self.call('finalize', False)

    def test_changed_binary_cannot_be_used(self):
        self.stage()
        self.call('finalize')
        (self.cache / 'dsl-closure').write_bytes(b'changed binary')
        self.call('check', False)


if __name__ == '__main__':
    unittest.main()
