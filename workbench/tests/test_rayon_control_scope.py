"""Exercise the real comparison guard against independent source mutations."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RayonControlScope(unittest.TestCase):
    def check_change(self, changed):
        command = next(line.strip() for line in (ROOT / '.github/workflows/build-cost.yml').read_text().splitlines()
                       if line.strip().startswith('git diff --exit-code "$reference" HEAD --'))
        files = ['program/rust-execution.ss', 'program/objects.ss', 'core/rule.ss',
                 'rust/ascent/src/execution/matching.rs', 'rust/ascent-scheme/src/lib.rs',
                 'rust/Cargo.lock', 'rust/Cargo.toml', 'gerbil.pkg', 'dev/gerbil.pkg', 'bindings/c/bridge.h']
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', '-C', str(root), *args], text=True, stderr=subprocess.PIPE)
            git('init', '-q')
            git('config', 'user.name', 'Control fixture')
            git('config', 'user.email', 'fixture@example.invalid')
            for name in files:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('reference\n')
            git('add', '.')
            git('-c', 'commit.gpgsign=false', 'commit', '-qm', 'reference')
            reference = git('rev-parse', 'HEAD').strip()
            (root / changed).write_text('candidate\n')
            git('add', changed)
            git('-c', 'commit.gpgsign=false', 'commit', '-qm', 'candidate')
            return subprocess.run(['bash', '-c', command], cwd=root, env=dict(os.environ, reference=reference),
                                  capture_output=True, text=True, timeout=10)

    def test_kernel_implementation_changes_are_compared(self):
        for path in ['program/rust-execution.ss', 'rust/ascent/src/execution/matching.rs']:
            with self.subTest(path=path):
                result = self.check_change(path)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_frontend_bridge_and_dependency_changes_still_reject(self):
        for path in ['program/objects.ss', 'core/rule.ss', 'bindings/c/bridge.h',
                     'rust/ascent-scheme/src/lib.rs', 'rust/Cargo.lock', 'rust/Cargo.toml',
                     'gerbil.pkg', 'dev/gerbil.pkg']:
            with self.subTest(path=path):
                result = self.check_change(path)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn(path, result.stdout)

    def test_build_only_producer_is_outside_the_vm_module_inventory(self):
        source = (ROOT / 'build-modules.ss').read_text()
        modules = re.search(r"\(def gerbil-ascent-library-modules\s+'\((.*?)\)\)", source, re.S)
        self.assertIsNotNone(modules)
        self.assertNotIn('program/rust-execution', re.findall(r'"([^"]+)"', modules.group(1)))
