# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""SDK compiler scope, exact cumulative counters and profile invalidation."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from ascent_workbench.preparation_work import gcc_ggc_bytes, gcc_ggc_complete, generated_scheme_input


class CompilerCostTests(unittest.TestCase):
    def test_full_runtime_control_rejects_missing_duplicate_or_compiled_source_suites(self):
        import runpy
        check = runpy.run_path('tools/ci/build-cost-control.py')['source_semantic_workload']
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / 't/qualification'
            source.mkdir(parents=True)
            for name in ['a-test.ss', 'b-test.ss']:
                (source / name).touch()
            log = root / 'run.log'
            valid = 'MODULE-OK t/qualification/b-test.ss\nMODULE-OK t/qualification/a-test.ss\nCASE-OK full case\n'
            log.write_text(valid)
            self.assertEqual(check(root, log)['cases'], 1)
            for invalid in [valid.replace('b-test.ss', 'a-test.ss'), valid.replace('CASE-OK full case', 'SKIPPED'),
                            valid.replace('MODULE-OK t/qualification/b-test.ss\n', '')]:
                log.write_text(invalid)
                with self.subTest(log=invalid), self.assertRaises(ValueError):
                    check(root, log)
            log.write_text(valid)
            compiled = root / '.gerbil/lib/gerbil-ascent/t/qualification/a-test.ssi'
            compiled.parent.mkdir(parents=True)
            compiled.touch()
            with self.assertRaises(ValueError):
                check(root, log)

    def test_generated_scheme_cost_requires_unique_containing_input(self):
        scheme = {'path': '/build/module~0.scm', 'sha256': 'source', 'bytes': 17}
        parent = {'pid': 7, 'inputs': [scheme]}
        helper = {'parent_gsc_observer': '7', 'inputs': [{'path': '/build/module~0.c'}],
                  'compiler_input_paths': ['/build/module~0.c']}
        self.assertEqual(generated_scheme_input(helper, parent), scheme)
        for changed in [dict(parent, pid=8), dict(parent, inputs=[]),
                        dict(parent, inputs=[scheme, scheme]),
                        dict(parent, inputs=[dict(scheme, path='/other/module~0.scm')])]:
            self.assertIsNone(generated_scheme_input(helper, changed))
        self.assertIsNone(generated_scheme_input(dict(helper, compiler_input_paths=[]), parent))

    def test_incomplete_or_changed_allocation_coverage_is_rejected(self):
        self.assertTrue(gcc_ggc_complete(3, 3, 0, 0, 0))
        for row in [(0,0,0,0,0), (3,2,0,0,0), (3,3,1,0,0), (3,3,0,1,0), (3,3,0,0,1)]:
            with self.subTest(row=row):
                self.assertFalse(gcc_ggc_complete(*row))

    def report(self, source):
        return {'version': '2.1.0', 'runs': [{
            'tool': {'driver': {'name': 'GNU C23', 'version': '16.2.0'}},
            'invocations': [{'executionSuccessful': True, 'arguments': [str(source)],
                'properties': {'gcc/timeReport': {'timevars': [
                    {'name': 'phase parsing', 'elapsed': {'ggc_mem': 300}},
                    {'name': 'nested pass', 'elapsed': {'ggc_mem': 200}},
                    {'name': 'TOTAL', 'elapsed': {'ggc_mem': 400}}]}}}],
            'artifacts': [{'location': {'uri': str(source)}, 'roles': ['analysisTarget']}]}]}

    def test_total_is_not_sum_of_overlapping_passes(self):
        source = Path('/tmp/owner.c').resolve()
        self.assertEqual(gcc_ggc_bytes(self.report(source), source), 400)

    def test_invalid_cumulative_counters_and_scope_are_rejected(self):
        source = Path('/tmp/owner.c').resolve()
        for value in [-1, True, 1.5, None, '400']:
            report = self.report(source)
            report['runs'][0]['invocations'][0]['properties']['gcc/timeReport']['timevars'][-1]['elapsed']['ggc_mem'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                gcc_ggc_bytes(report, source)
        report = self.report(source)
        report['runs'][0]['tool']['driver']['name'] = 'Scheme VM occupancy'
        with self.assertRaises(ValueError):
            gcc_ggc_bytes(report, source)

    def test_relative_input_is_bound_to_compiler_origin_not_summary_directory(self):
        source = Path('/tmp/native-compiler-origin/owner.c').resolve()
        report = self.report(source)
        run = report['runs'][0]
        run['originalUriBaseIds'] = {'PWD': {'uri': source.parent.as_uri() + '/'}}
        run['artifacts'][0]['location'] = {'uri': source.name, 'uriBaseId': 'PWD'}
        invocation = run['invocations'][0]
        invocation['workingDirectory'] = {'uri': str(source.parent)}
        invocation['arguments'] = [source.name, source.name, '.c']
        self.assertEqual(gcc_ggc_bytes(report, source), 400)
        for changed in ['workingDirectory', 'uriBaseId', 'originalUriBaseIds']:
            invalid = copy.deepcopy(report)
            if changed == 'workingDirectory':
                invalid['runs'][0]['invocations'][0]['workingDirectory']['uri'] = '/tmp/wrong-origin'
            elif changed == 'uriBaseId':
                invalid['runs'][0]['artifacts'][0]['location']['uriBaseId'] = 'MISSING'
            else:
                invalid['runs'][0]['originalUriBaseIds']['PWD']['uri'] = 'https://invalid.test/'
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                gcc_ggc_bytes(invalid, source)

    def test_wrong_input_partial_duplicate_or_malformed_report_is_rejected(self):
        source = Path('/tmp/owner.c').resolve()
        report = self.report(source)
        variants = [None, [], {}, {'version': '2.1.0', 'runs': [None]}, copy.deepcopy(report)]
        variants[-1]['runs'][0]['invocations'][0]['executionSuccessful'] = False
        duplicate = copy.deepcopy(report)
        timers = duplicate['runs'][0]['invocations'][0]['properties']['gcc/timeReport']['timevars']
        timers.append(copy.deepcopy(timers[-1]))
        variants.append(duplicate)
        duplicate_target = copy.deepcopy(report)
        duplicate_target['runs'][0]['artifacts'].append(copy.deepcopy(duplicate_target['runs'][0]['artifacts'][0]))
        variants.append(duplicate_target)
        for invalid in variants:
            with self.subTest(report=invalid), self.assertRaises(ValueError):
                gcc_ggc_bytes(invalid, source)
        with self.assertRaises(ValueError):
            gcc_ggc_bytes(report, source.with_name('other.c'))

    @unittest.skipUnless(shutil.which('gxi'), 'released Gerbil SDK required')
    def test_compiler_option_receipt_rejects_mismatch_truncation_and_trailing_data(self):
        module = Path('t/harness/artifact-admission.ss').resolve()
        with tempfile.TemporaryDirectory() as folder:
            record = Path(folder) / 'options.sexp'
            expression = f'''(import {json.dumps(str(module))})
(def file {json.dumps(str(record))})
(def options '("-cc-options" "-D___SINGLE_HOST_LIMIT=512"))
(write (artifact-compiler-options-current? file options)) (newline)
(artifact-record-compiler-options! file options)
(write (list (artifact-compiler-options-current? file options)
             (artifact-compiler-options-current? file '("-cc-options" "-D___SINGLE_HOST_LIMIT=0")))) (newline)
(call-with-output-file [path: file append: #t] (lambda (port) (write 'trailing port)))
(write (artifact-compiler-options-current? file options)) (newline)
(call-with-output-file [path: file truncate: #t] (lambda (port) (display "(" port)))
(write (artifact-compiler-options-current? file options)) (newline)
'''
            process = subprocess.run(['gxi', '-:max-heap=1G,debug=q', '-e', expression], capture_output=True, text=True, timeout=30)
            self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
            self.assertEqual(process.stdout.splitlines(), ['#f', '(#t #f)', '#f', '#f'])

    @unittest.skipUnless(shutil.which('gxi'), 'released Gerbil SDK required')
    def test_sdk_c_layout_preserves_tail_calls_values_and_single_processor(self):
        source_text = '''package: compiler-check
(import :std/ffi)
(C-ffi-macrology)
(export total host-limit extra-option)
(C-declare "#ifndef ___SINGLE_HOST_LIMIT\\n#define ___SINGLE_HOST_LIMIT 0\\n#endif")
(def-C-lambda (host-limit) => int "___return(___SINGLE_HOST_LIMIT);")
(def-C-lambda (extra-option) => int "___return(ASCENT_TEST_CC_OPTION);")
(def (total n)
 (let loop ((n n) (sum 0))
  (if (zero? n) sum (loop (- n 1) (+ sum n)))))
'''
        for limit in [0, 1, 512]:
            with self.subTest(limit=limit), tempfile.TemporaryDirectory() as folder:
                root = Path(folder).resolve()
                source = root / 'producer.ss'
                source.write_text(source_text)
                library = root / 'lib'
                library.mkdir()
                expression = f'''(import :std/make)
(make '((gxc: "producer" "-cc-options" "-DASCENT_TEST_CC_OPTION=17" "-cc-options" "-D___SINGLE_HOST_LIMIT={limit}"))
      srcdir: {json.dumps(str(root))} libdir: {json.dumps(str(library))}
      prefix: "compiler-check" optimize: #t parallelize: 3)
'''
                compiled = subprocess.run(['gxi', '-:max-heap=1G,debug=q', '-e', expression], cwd=root,
                                          capture_output=True, text=True, timeout=30)
                self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
                expression = f'''(add-load-path! {json.dumps(str(library))})
(import :compiler-check/producer)
(write (list (total 100000) (host-limit) (extra-option) (##current-vm-processor-count))) (newline)
'''
                invoked = subprocess.run(['gxi', '-:max-heap=1G,debug=q', '-e', expression], cwd=root,
                                         capture_output=True, text=True, timeout=30)
                self.assertEqual(invoked.returncode, 0, invoked.stdout + invoked.stderr)
                self.assertEqual(invoked.stdout.strip(), f'(5000050000 {limit} 17 1)')

    @unittest.skipUnless(shutil.which('gxi'), 'released Gerbil SDK required')
    def test_object_counter_and_link_metadata_have_distinct_cost_roles(self):
        from ascent_workbench.preparation_work import install, summarize
        import os
        sdk = Path(subprocess.check_output(['gxi', '-e', '(display (gerbil-home))'], text=True).strip())
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            source = root / 'input.c'
            source.write_text('int ascent_probe(int x) { return x + 1; }\n')
            obj = root / 'different.o'
            for operation, inputs, output in [('obj', source.name, obj), ('dyn', obj.name, root / 'linked.o1')]:
                observer = root / operation
                env = dict(os.environ, **install(observer, sdk / 'bin/gxi', sdk / 'bin/gsc'))
                env.update(GAMBITDIR_INCLUDE=str(sdk / 'include'), GAMBITDIR_LIB=str(sdk / 'lib'))
                env.update({f'BUILD_{operation.upper()}_INPUT_FILENAMES_PARAM': inputs,
                            f'BUILD_{operation.upper()}_META_INFO_FILE_PARAM': source.name,
                            f'BUILD_{operation.upper()}_OUTPUT_FILENAME_PARAM': str(output)})
                process = subprocess.run([str(observer / 'gambuild-C'), operation], env=env, cwd=root,
                                         capture_output=True, text=True, timeout=30)
                self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
                (observer / 'gsc-records').rename(observer / 'prepare')
                phase = summarize(observer)['phases']['prepare']
                record = json.loads(next((observer / 'prepare').glob('*.json')).read_text())
                self.assertIn(str(source), [i['path'] for i in record['inputs']])
                if operation == 'obj':
                    self.assertTrue(phase['gcc_cumulative_ggc_observed'])
                    self.assertGreater(phase['gcc_cumulative_ggc_bytes'], 0)
                else:
                    self.assertEqual(record['compiler_input_paths'], [str(obj)])
                    self.assertNotIn('gcc_report_expected', record)
                    self.assertEqual(phase['gcc_allocation_errors'], [])
                    self.assertFalse(phase['gcc_cumulative_ggc_observed'])

    @unittest.skipUnless(shutil.which('gxi'), 'released Gerbil SDK required')
    def test_gcc_counter_is_retained_and_bound_to_its_real_input(self):
        from ascent_workbench.preparation_work import install, summarize
        import os
        sdk = Path(subprocess.check_output(['gxi', '-e', '(display (gerbil-home))'], text=True).strip())
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            source = root / 'owned.c'
            source.write_text('#include "gambit.h"\nint ascent_probe(int x) { return x + 1; }\n')
            observer = root / 'observer'
            env = dict(os.environ, **install(observer, sdk / 'bin/gxi', sdk / 'bin/gsc'))
            env.update(GAMBITDIR_INCLUDE=str(sdk / 'include'), GAMBITDIR_LIB=str(sdk / 'lib'),
                       BUILD_DYN_INPUT_FILENAMES_PARAM=source.name, BUILD_DYN_META_INFO_FILE_PARAM=source.name,
                       BUILD_DYN_OUTPUT_FILENAME_PARAM=str(root / 'owned.o1'))
            process = subprocess.run([str(observer / 'gambuild-C'), 'dyn'], env=env,
                                     capture_output=True, text=True, timeout=30, cwd=root)
            self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
            (observer / 'gsc-records').rename(observer / 'prepare')
            phase = summarize(observer)['phases']['prepare']
            self.assertTrue(phase['gcc_cumulative_ggc_observed'])
            self.assertGreater(phase['gcc_cumulative_ggc_bytes'], 0)
            self.assertFalse(phase['cumulative_allocation_observed'])
            record_path, = (observer / 'prepare').glob('*.json')
            record = json.loads(record_path.read_text())
            report_path = observer / 'inputs' / record['gcc_report']['sha256']
            report_path.write_text('{}')
            with self.assertRaisesRegex(ValueError, 'damaged GCC allocation report'):
                summarize(observer)
