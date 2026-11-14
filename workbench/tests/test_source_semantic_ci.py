"""Source CI phase isolation must preserve the complete semantic gate."""
import importlib.util
import json
import os
import shutil
import subprocess
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
    def test_cost_control_builds_production_before_development_policy(self):
        import ast
        self.assertEqual(CONTROL.control_build_command(), ['gerbil', 'build'])
        module = ast.parse((ROOT / 'tools/ci/build-cost-control.py').read_text())
        loops = [node for node in ast.walk(module) if isinstance(node, ast.For)
                 and ast.unparse(node.target) == '(phase, command)']
        self.assertEqual(len(loops), 1)
        phases = loops[0].iter.elts
        self.assertEqual([item.elts[0].value for item in phases], ['build', 'policy', 'prepare'])
        self.assertEqual(ast.unparse(phases[0].elts[1]), 'control_build_command()')
        self.assertEqual(ast.literal_eval(phases[1].elts[1]), ['just', 'check-policy'])

    @unittest.skipUnless(shutil.which('gxi'), 'released SDK required')
    def test_native_runtime_resolves_prepared_dependency_and_keeps_suite_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            source = root / 'sample/producer.ss'
            source.parent.mkdir()
            source.write_text('package: sample\n(export value)\n(def value 1)\n')
            suite = root / 'sample/suite-test.ss'
            suite.write_text('package: sample\n(import :sample/producer)\n(export)\n')
            library = root / '.gerbil/lib'
            library.mkdir(parents=True)
            compile_expression = ('(import :gerbil/compiler) '
                f'(compile-module {json.dumps(str(source))} '
                f'[output-dir: {json.dumps(str(library))} invoke-gsc: #f optimize: #f])')
            subprocess.run(['gxi', '-:p1,max-heap=1G,debug=q', '-e', compile_expression],
                           capture_output=True, text=True, check=True, timeout=30)
            interface = library / 'sample/producer.ssi'
            self.assertTrue(interface.exists())
            expression = ('(import :gerbil/expander) '
                "(write (module-context-path (import-module ':sample/producer #f #f))) (newline) "
                f'(write (module-context-path (import-module {json.dumps(str(suite))} #f #f))) (newline)')
            inherited = dict(os.environ, GERBIL_PATH=str(root / '.gerbil'),
                             GERBIL_LOADPATH=str(root), ASCENT_TEST_LIBRARY='forbidden')
            old = subprocess.run(['gxi', '-:p1,max-heap=1G,debug=q', '-e', expression],
                                 env=inherited, cwd=root, capture_output=True, text=True, check=True, timeout=30)
            fixed = CONTROL.source_semantic_environment(root, inherited)
            self.assertNotIn('ASCENT_TEST_LIBRARY', fixed)
            new = subprocess.run(['gxi', '-:p1,max-heap=1G,debug=q', '-e', expression],
                                 env=fixed, cwd=root, capture_output=True, text=True, check=True, timeout=30)
            self.assertEqual(old.stdout.splitlines(), [json.dumps(str(source)), json.dumps(str(suite))])
            self.assertEqual(new.stdout.splitlines(), [json.dumps(str(interface)), json.dumps(str(suite))])

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
                             ['timeout', '600s', 'just', 'test-file', 't/qualification', '2G'])
            self.assertEqual(measure.call_args.args[3]['GERBIL_BUILD_CORES'], '12')
            self.assertEqual(measure.call_args.args[3]['GERBIL_LOADPATH'], str(root / '.gerbil/lib'))
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

    def test_completed_native_log_is_verified_without_launching_a_process(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 't/qualification/entry-test.ss'
            source.parent.mkdir(parents=True)
            source.write_text('(export)\n')
            log = root / 'native.log'
            log.write_text('TEST-DISPATCH modules=1 batches=1 workers=12 max-batch-modules=1 mode=batched\n'
                           'VM-RUNTIME processors=1\nCASE-OK entry\nMODULE-OK t/qualification/entry-test.ss\n')
            output = root / 'verified'
            with patch.object(Path, 'cwd', return_value=root), \
                    patch.object(sys, 'argv', ['control', '--verify-source-log', str(log), '--output', str(output)]), \
                    patch.object(CONTROL.subprocess, 'run') as launch:
                CONTROL.main()
            launch.assert_not_called()
            self.assertEqual(json.loads((output / 'source-runtime-workload.json').read_text())['cases'], 1)
            for invalid in [log.read_text().replace('workers=12', 'workers=1'),
                            log.read_text().replace('processors=1', 'processors=2'),
                            log.read_text().replace('MODULE-OK t/qualification/entry-test.ss', '')]:
                log.write_text(invalid)
                with self.assertRaises(ValueError):
                    CONTROL.source_semantic_workload(root, log)
            log.write_text('TEST-DISPATCH modules=1 batches=1 workers=12 max-batch-modules=1 mode=batched\n'
                           'VM-RUNTIME processors=1\nCASE-OK entry\nMODULE-OK t/qualification/entry-test.ss\n')
            compiled = root / '.gerbil/lib/gerbil-ascent/t/qualification/entry-test.ssi'
            compiled.parent.mkdir(parents=True)
            compiled.write_text('stale compiled Suite')
            with self.assertRaisesRegex(ValueError, 'incomplete or compiled'):
                CONTROL.source_semantic_workload(root, log)

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
                    self.assertEqual(call.args[2]['ASCENT_GXTEST_TIMEOUT'], '600s')
                    self.assertNotIn('ASCENT_TEST_LIBRARY', call.args[2])
                receipts.append(json.loads((output / 'inputs.json').read_text()))
            self.assertEqual(receipts[0], receipts[1])
            self.assertEqual(receipts[1], receipts[2])
            self.assertEqual(receipts[0]['scheme_vm_workers'], 12)
            self.assertEqual(receipts[0]['threads_per_vm'], 1)
            self.assertEqual(receipts[0]['cores'], 3)


if __name__ == '__main__':
    unittest.main()
