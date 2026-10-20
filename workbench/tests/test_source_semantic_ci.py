"""Source CI phase isolation must preserve the complete semantic gate."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('source_semantic_control', ROOT / 'tools/ci/build-cost-control.py')
CONTROL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTROL)


class SourceSemanticCiTests(unittest.TestCase):
    def test_timeout_preserves_batch_diagnostics_and_original_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            batches = root / '.cache/ascent/test-modules'
            batches.mkdir(parents=True)
            (batches / 'incomplete.log').write_text('CASE still running\n')
            output = root / 'receipt'
            output.mkdir()
            with patch.object(CONTROL, 'measure', side_effect=RuntimeError('exit=124')) as measure:
                with self.assertRaisesRegex(RuntimeError, 'exit=124'):
                    CONTROL.run_source_semantics(root, output, {'GERBIL_BUILD_CORES': '3'})
            self.assertEqual(measure.call_args.args[1],
                             ['timeout', '240s', 'just', 'test-file', 't/qualification', '2G'])
            self.assertEqual(measure.call_args.args[3]['GERBIL_BUILD_CORES'], '12')
            self.assertTrue(measure.call_args.kwargs['semantic_diagnostics'])
            self.assertEqual((output / 'semantic-batches/incomplete.log').read_text(), 'CASE still running\n')

    def test_compiled_suite_carriers_are_still_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 't/qualification/example-test.ss'
            source.parent.mkdir(parents=True)
            source.write_text('(export)\n')
            compiled = root / '.gerbil/lib/gerbil-ascent/t/qualification/example-test.ssi'
            compiled.parent.mkdir(parents=True)
            compiled.write_text('compiled')
            output = root / 'receipt'
            output.mkdir()
            with patch.object(CONTROL, 'measure') as measure:
                with self.assertRaisesRegex(RuntimeError, 'compiled Suite carriers'):
                    CONTROL.run_source_semantics(root, output, {})
            measure.assert_not_called()

    def invoke(self, root, arguments):
        output = root / arguments[-1]
        arguments = [*arguments[:-1], str(output)]
        with patch.object(Path, 'cwd', return_value=root), \
                patch.dict(os.environ, GERBIL_PREFIX=str(root)), \
                patch.object(sys, 'argv', ['control', '--semantics-only', *arguments]), \
                patch.object(CONTROL.subprocess, 'check_output', return_value='fixed-head\n'):
            CONTROL.main()
        return output

    def test_cache_failure_does_not_skip_complete_runtime_in_combined_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'gerbil-build-receipt.json').write_text('{}')
            with patch.object(CONTROL, 'prepare_source_semantics') as prepare, \
                    patch.object(CONTROL, 'check_source_semantic_cache', return_value='cache rejected'), \
                    patch.object(CONTROL, 'run_source_semantics') as run:
                with self.assertRaisesRegex(RuntimeError, 'cache rejected'):
                    self.invoke(root, ['--output', 'all'])
            prepare.assert_called_once()
            run.assert_called_once()

    def test_phases_select_only_their_operation_and_retain_same_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'gerbil-build-receipt.json').write_text('{}')
            receipts = []
            for phase, selected in [('prepare', 0), ('cache', 1), ('run', 2)]:
                with patch.object(CONTROL, 'prepare_source_semantics') as prepare, \
                        patch.object(CONTROL, 'check_source_semantic_cache', return_value=None) as cache, \
                        patch.object(CONTROL, 'run_source_semantics') as run:
                    output = self.invoke(root, ['--semantic-phase', phase, '--output', phase])
                    self.assertEqual([item.call_count for item in [prepare, cache, run]],
                                     [int(index == selected) for index in range(3)])
                    call = [prepare, cache, run][selected].call_args
                    self.assertEqual(call.args[2]['ASCENT_GXTEST_TIMEOUT'], '240s')
                    self.assertNotIn('ASCENT_TEST_LIBRARY', call.args[2])
                receipts.append(json.loads((output / 'inputs.json').read_text()))
            self.assertEqual(receipts[0], receipts[1])
            self.assertEqual(receipts[1], receipts[2])
            self.assertEqual(receipts[0]['scheme_vm_workers'], 12)
            self.assertEqual(receipts[0]['threads_per_vm'], 1)
            self.assertEqual(receipts[0]['cores'], 3)


if __name__ == '__main__':
    unittest.main()
