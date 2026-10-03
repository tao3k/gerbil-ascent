"""Reject drift in a native qualification snapshot before accepting results."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'performance_execution.py'
spec = importlib.util.spec_from_file_location('performance_execution', SCRIPT)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class SnapshotTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.root_patch = patch.object(runner, 'ROOT', self.root)
        self.root_patch.start()
        self.dependency_patch = patch.object(runner, 'dependencies', return_value={})
        self.dependency_patch.start()
        paths = ['program/evaluate.ss', 'program/session.ss', 'gerbil.pkg', 'justfile',
                 'tools/build-performance-library.ss', 'tools/performance_execution.py',
                 't/performance/ascent-ss-profile.ss', 't/performance/native-library.ss',
                 't/performance/ascent-scenario-performance-test.ss', *runner.SPECIAL.values()]
        for name in paths:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('original\n')
        (self.root / 'build.ss').write_text(
            '(def gerbil-ascent-library-modules \'("program/evaluate" "program/session"))\n')
        self.artifact = self.root / 'lib/program/evaluate.ssi'
        self.artifact.parent.mkdir(parents=True)
        self.artifact.write_text('native artifact\n')
        modules, sources = runner.source_manifest()
        self.snapshot = dict(modules=modules, sources=sources, dependencies={},
                             artifacts={str(self.artifact): runner.digest(self.artifact)})

    def tearDown(self):
        self.root_patch.stop()
        self.dependency_patch.stop()
        self.temporary.cleanup()

    def test_unchanged_snapshot_is_accepted(self):
        self.assertEqual(runner.verify(self.snapshot), ['program/evaluate', 'program/session'])

    def test_source_changed_after_build_is_rejected(self):
        (self.root / 'program/session.ss').write_text('changed\n')
        with self.assertRaisesRegex(ValueError, 'production source changed'):
            runner.verify(self.snapshot)

    def test_benchmark_budget_changed_after_build_is_rejected(self):
        (self.root / 't/performance/ascent-ss-profile.ss').write_text('changed\n')
        with self.assertRaisesRegex(ValueError, 'production source changed'):
            runner.verify(self.snapshot)

    def test_changed_artifact_is_rejected(self):
        self.artifact.write_text('different native artifact\n')
        with self.assertRaisesRegex(ValueError, 'artifact changed'):
            runner.verify(self.snapshot)

    def test_missing_artifact_is_rejected(self):
        self.artifact.unlink()
        with self.assertRaises(FileNotFoundError):
            runner.verify(self.snapshot)

    def test_changed_dependency_is_rejected(self):
        runner.dependencies.return_value = {'dependency.ssi': 'changed'}
        with self.assertRaisesRegex(ValueError, 'dependency artifacts changed'):
            runner.verify(self.snapshot)

    def test_unknown_scenario_is_rejected_before_build(self):
        with patch.object(runner.sys, 'argv', ['performance_execution.py', '../bad']), \
             patch.object(runner, 'prepare') as prepare:
            with self.assertRaisesRegex(ValueError, 'unknown performance scenario'):
                runner.main()
            prepare.assert_not_called()


if __name__ == '__main__':
    unittest.main()
