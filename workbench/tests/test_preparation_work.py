# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from ascent_workbench.preparation_work import install, summarize


class PreparationWorkTests(unittest.TestCase):
    def test_env_shebang_enters_sdk_through_import_observer(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            sdk = root / 'sdk'
            sdk.mkdir()
            real = sdk / 'gxi'
            real.write_text(f'#!{sys.executable}\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n')
            real.chmod(0o755)
            (sdk / 'gambuild-C').touch()
            observer = root / 'observer'
            env = dict(os.environ, **install(observer, real, sdk / 'gsc'))
            script = root / 'build.ss'
            script.write_text('#!/usr/bin/env gxi\n')
            script.chmod(0o755)
            process = subprocess.run([str(script), 'compile'], env=env,
                                     check=True, capture_output=True, text=True)
            arguments = json.loads(process.stdout)
            self.assertEqual(arguments[0], '-e')
            self.assertIn('current-expander-module-import', arguments[1])
            self.assertEqual(arguments[2:], [str(script), 'compile'])

    def test_sdk_helper_keeps_original_sibling_directory_and_exit(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            sdk = root / 'sdk'
            sdk.mkdir()
            helper = sdk / 'gambuild-C'
            helper.write_text('#!/bin/sh\nprintf "%s\\n" "$0" "$1"\nexit 9\n')
            helper.chmod(0o755)
            observer = root / 'observer'
            env = dict(os.environ, **install(observer, sdk / 'gxi', sdk / 'gsc'))
            process = subprocess.run([str(observer / 'gambuild-C'), 'dyn'], env=env, capture_output=True, text=True)
            self.assertEqual(process.returncode, 9)
            self.assertEqual(process.stdout.splitlines(), [str(helper), 'dyn'])

    def test_internal_sdk_helper_is_attributed_without_changing_sdk_root(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            sdk = root / 'sdk' / 'bin'
            sdk.mkdir(parents=True)
            helper = sdk / 'gambuild-C'
            helper.write_text('#!/bin/sh\nprintf "%s\\n" "$0" "$1"\nexit 9\n')
            helper.chmod(0o755)
            real = sdk / 'gsc'
            real.write_text(f'#!{sys.executable}\nimport subprocess,sys\n'
                            f'assert sys.argv[1].startswith("-:~~=" + {str(sdk.parent)!r} + ",~~bin=")\n'
                            'directory=sys.argv[1].split(",~~bin=",1)[1]\n'
                            'sys.exit(subprocess.run([directory+"/gambuild-C", "dyn"]).returncode)\n')
            real.chmod(0o755)
            observer = root / 'observer'
            env = dict(os.environ, **install(observer, sdk / 'gxi', real))
            process = subprocess.run([str(observer / 'gsc'), '-dynamic'], env=env,
                                     capture_output=True, text=True)
            self.assertEqual(process.returncode, 9)
            self.assertEqual(process.stdout.splitlines(), [str(helper), 'dyn'])
            records = [json.loads(p.read_text()) for p in (observer / 'gsc-records').glob('*.json')]
            outer, = [r for r in records if r['kind'] == 'gsc']
            inner, = [r for r in records if r['kind'] == 'sdk-helper']
            self.assertEqual(inner['parent_gsc_observer'], str(outer['pid']))
            self.assertEqual(outer['arguments'], ['-dynamic'])
            self.assertLessEqual(outer['process_wall_ns'], outer['wall_ns'])
            (observer / 'gsc-records').rename(observer / 'prepare')
            phase = summarize(observer)['phases']['prepare']
            self.assertEqual(phase['nested_sdk_helper_invocations'], 1)
            self.assertEqual(phase['nested_sdk_helper_cpu_seconds'],
                             inner['user_seconds'] + inner['system_seconds'])
            self.assertTrue(phase['internal_helper_observer_enabled'])
            self.assertAlmostEqual(phase['gsc_residual_cpu_seconds'] +
                                   phase['nested_sdk_helper_cpu_seconds'], phase['gsc_cpu_seconds'])
            inner_path, = [p for p in (observer / 'prepare').glob('*.json')
                           if json.loads(p.read_text())['kind'] == 'sdk-helper']
            inner_path.write_text(json.dumps(dict(inner, user_seconds=10**9)))
            with self.assertRaisesRegex(ValueError, 'exceeds containing GSC'):
                summarize(observer)
            inner_path.write_text(json.dumps(inner))
            for p in (observer / 'prepare').glob('*.json'):
                if json.loads(p.read_text())['kind'] == 'gsc':
                    p.unlink()
            with self.assertRaisesRegex(ValueError, 'no containing GSC'):
                summarize(observer)

    def test_nested_process_allocations_are_not_added(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'prepare-imports.sexp').write_text(
                '(import-work 1 1 "child.ss" 2 3 100 20 0 10 5 0 0 0)\n'
                '(import-work 0 0 "parent.ss" 1 4 100 40 1 20 10 2 1 3)\n')
            result = summarize(root)
            phase = result['phases']['prepare']
            self.assertEqual(phase['import_requests'], 2)
            self.assertEqual(phase['direct_registry_hits'], 1)
            self.assertEqual(phase['largest_inclusive_imports'][0]['sdk_allocated_bytes'], 40)
            self.assertEqual(phase['largest_gc_imports'][0]['gc_cpu_ns'], 3)
            self.assertNotIn('total_allocated_bytes', phase)
            self.assertFalse(result['latency_admitted'])
            self.assertFalse(result['compiler_allocator_source_refinement'])
            (root / 'prepare-imports.sexp').write_text('(import-work 0 0 "gc.ss" 1 2 100 -10 0 1 1 0 0 0)\n')
            decreased = summarize(root)['phases']['prepare']['negative_sdk_allocation_estimates']
            self.assertEqual(decreased[0]['sdk_allocated_bytes'], -10)
            (root / 'prepare-imports.sexp').write_text('(import-work 0 "unfinished')
            with self.assertRaises(ValueError):
                summarize(root)

    def test_raw_counter_drop_rejects_even_positive_corrected_estimate(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            trace = root / 'prepare-imports.sexp'
            trace.write_text('(import-work-v3 0 0 "gc.ss" 1 2 100 20 1 1 1 0 0 0 8000 100)\n')
            phase = summarize(root)['phases']['prepare']
            self.assertEqual(len(phase['raw_counter_decreases']), 1)
            self.assertFalse(phase['observations_complete'])
            self.assertEqual(phase['negative_sdk_allocation_estimates'], [])
            trace.write_text('(import-work-v3 0 0 "gc.ss" 1 2 100 20 1 1 1 0 0 0)\n')
            with self.assertRaisesRegex(ValueError, 'version mismatch'):
                summarize(root)

    def test_failed_compiler_keeps_exact_inputs_and_exit(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / 'a.scm'
            source.write_bytes(b'(display "test")\n')
            output = root / 'previous.c'
            output.write_bytes(b'old output is not compiler input')
            real = root / 'compiler'
            real.write_text(f'#!{sys.executable}\nimport sys\nsys.exit(7)\n')
            real.chmod(0o755)
            records = root / 'prepare'
            records.mkdir()
            env = os.environ.copy()
            env.update(ASCENT_REAL_GSC=str(real), ASCENT_GSC_WORK_DIRECTORY=str(records))
            process = subprocess.run([sys.executable, '-m', 'ascent_workbench.preparation_work',
                                      '-o', str(output), str(source)], env=env)
            self.assertEqual(process.returncode, 7)
            record, = [json.loads(p.read_text()) for p in records.glob('*.json')]
            self.assertEqual(record['inputs'][0]['sha256'], hashlib.sha256(source.read_bytes()).hexdigest())
            self.assertEqual(len(record['inputs']), 1)
            blob = root / 'inputs' / record['inputs'][0]['sha256']
            self.assertEqual(blob.read_bytes(), source.read_bytes())
            summary = summarize(root)['phases']['prepare']
            self.assertEqual(summary['gsc_invocations'], 1)
            self.assertEqual(summary['gsc_failed'], 1)
            self.assertEqual(summary['gsc_input_bytes'], source.stat().st_size)
            self.assertFalse(summary['import_observer_ran'])
            self.assertFalse(summary['observations_complete'])
            # A correct digest with a fabricated byte count corrupts the cost basis.
            original_bytes = record['inputs'][0]['bytes']
            record['inputs'][0]['bytes'] += 1
            next(records.glob('*.json')).write_text(json.dumps(record))
            with self.assertRaisesRegex(ValueError, 'expanded compiler input'):
                summarize(root)
            record['inputs'][0]['bytes'] = original_bytes
            next(records.glob('*.json')).write_text(json.dumps(record))
            blob.write_bytes(b'damaged retained input')
            with self.assertRaisesRegex(ValueError, 'expanded compiler input'):
                summarize(root)

    def test_helper_failure_and_changed_inputs_cannot_qualify_work(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            phase = root / 'prepare'
            phase.mkdir()
            (root / 'prepare-imports.sexp').write_text('')
            record = {'kind': 'sdk-helper', 'inputs': [], 'exit_code': 0,
                      'inputs_current': True, 'user_seconds': 0, 'system_seconds': 0}
            path = phase / 'helper.json'
            path.write_text(json.dumps(record))
            self.assertTrue(summarize(root)['phases']['prepare']['observations_complete'])
            for key, bad in (('exit_code', 7), ('inputs_current', False)):
                with self.subTest(key=key):
                    path.write_text(json.dumps(dict(record, **{key: bad})))
                    result = summarize(root)['phases']['prepare']
                    self.assertFalse(result['observations_complete'])
