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

from ascent_workbench.preparation_work import gcc_ggc_bytes, gcc_pass_costs, gcc_ggc_complete, generated_scheme_input, generated_source_producer, compiler_output_paths, compiler_allocation_total, source_cost_coverage


class CompilerCostTests(unittest.TestCase):
    def test_runtime_only_edits_preserve_restore_compatibility_but_change_exact_source_key(self):
        import hashlib
        import re
        workflow = Path('.github/workflows/build-cost.yml').read_text()
        selection = re.search(r'compiler_inputs="\$\(git ls-files -s -- (.*?) \| sha256sum', workflow).group(1).split()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', '-C', str(root), *args])
            git('init', '-q')
            inputs = ['build.ss', 'build-modules.ss', 'gerbil.pkg', 'dev/gerbil.pkg', 'bindings/c/ascent.h',
                      't/harness/build.ss', 't/harness/artifact-admission.ss', 't/harness/library-spec.ss',
                      't/harness/test.ss', '.github/workflows/build-cost.yml', 'justfile']
            for name in inputs:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('initial\n')
            git('add', '.')
            def compatibility():
                return hashlib.sha256(git('ls-files', '-s', '--', *selection)).hexdigest()
            def exact():
                return hashlib.sha256(git('ls-files', '-s')).hexdigest()
            compatible, current = compatibility(), exact()
            for name in ['t/harness/test.ss', '.github/workflows/build-cost.yml', 'justfile']:
                (root / name).write_text('changed runtime orchestration\n')
                git('add', name)
                self.assertEqual(compatibility(), compatible, name)
                self.assertNotEqual(exact(), current, name)
                current = exact()
            for name in ['build.ss', 'build-modules.ss', 'gerbil.pkg', 'dev/gerbil.pkg', 'bindings/c/ascent.h',
                         't/harness/build.ss', 't/harness/artifact-admission.ss', 't/harness/library-spec.ss']:
                previous = compatibility()
                (root / name).write_text('changed compiler or dependency input\n')
                git('add', name)
                self.assertNotEqual(compatibility(), previous, name)

    def test_shared_frozen_carriers_keep_original_bodies_and_absolute_dependencies(self):
        import hashlib
        for name, digest in [
            ('reference-initialization', 'c7f86dcef7295fe4f198eaad0b7b66f62ad4658f359d1457a89a4a755e95713e'),
            ('reference-view-replay', '3ff78c5d8f9fc322ba279652eda0b233256d3a1d63c44411249247102f3a2893'),
        ]:
            body = Path('t/performance/uf-dense', name + '.ss').read_bytes()
            self.assertEqual(hashlib.sha256(body).hexdigest(), digest)
            self.assertNotIn(b'"reference-', body)

    def test_unknown_cc_options_are_not_the_observed_sdk_default(self):
        from ascent_workbench.preparation_work import cc_options_observed
        for unknown in [None, False, 0, [], {}]:
            self.assertFalse(cc_options_observed(unknown))
        self.assertTrue(cc_options_observed(''))
        self.assertTrue(cc_options_observed('-D___SINGLE_HOST_LIMIT=512'))

    def test_builder_phase_decoder_preserves_exponents_and_rejects_partial_values(self):
        import runpy
        decode = runpy.run_path('tools/ci/build-cost-control.py')['builder_phases']
        prefix = 'BUILD-TEST-LIBRARY-PHASE source-context-reuse wall-seconds='
        for text, value in [('1.1e-5', 0.000011), ('.10284', 0.10284), ('4.54305', 4.54305),
                            ('0', 0.0), ('0.', 0.0), ('1.', 1.0), ('1E+2', 100.0)]:
            self.assertEqual(decode(prefix + text), {'source-context-reuse': value})
        for text in ['nan', 'inf', '-1', '1e999', '1.1e', '1.1e-5junk', '1..2', '1 2']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                decode(prefix + text)

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
            valid = 'TEST-DISPATCH modules=2 batches=12 workers=12 max-batch-modules=1 mode=batched heap=2G\nMODULE-OK t/qualification/b-test.ss\nMODULE-OK t/qualification/a-test.ss\nCASE-OK full case\n'
            valid += 'VM-RUNTIME processors=1\n' * 12
            log.write_text(valid)
            self.assertEqual(check(root, log)['cases'], 1)
            for invalid in [valid.replace('max-batch-modules=1', 'max-batch-modules=2'), valid.replace('processors=1', 'processors=2'), valid.replace('VM-RUNTIME processors=1\n', '', 1), valid.replace('workers=12', 'workers=3'), valid.replace('b-test.ss', 'a-test.ss'), valid.replace('CASE-OK full case', 'SKIPPED'),
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

    def test_native_refinement_width_covers_empty_and_complete_source_selection(self):
        import runpy
        width = runpy.run_path('tools/ci/build-cost-control.py')['source_batch_width']
        self.assertEqual(width(width(174, 12), 12), 2)
        for workers in [1, 2, 3, 12, 48]:
            for entries in [0, 1, 2, 12, 37, 174, 253]:
                self.assertEqual(width(entries, workers), (entries + workers - 1) // workers)
                self.assertLessEqual(width(width(entries, workers), workers), width(entries, workers))

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

    def test_static_copy_cost_requires_successful_prior_content_producer(self):
        scheme = {'path': '/build/module~0.scm', 'sha256': 'scheme', 'bytes': 17}
        copied = {'path': '/build/static/module.c', 'sha256': 'c-output', 'bytes': 29}
        output = dict(copied, path='/build/module~0.c')
        parent = {'pid': 7, 'started_ns': 100, 'inputs': [copied]}
        helper = {'parent_gsc_observer': '7', 'inputs': [copied],
                  'compiler_input_paths': [copied['path']]}
        producer = {'pid': 2, 'finished_ns': 90, 'exit_code': 0, 'inputs_current': True,
                    'arguments': ['-c', '-o', output['path'], scheme['path']],
                    'inputs': [scheme], 'outputs': [output]}
        found = generated_source_producer(helper, parent, [producer])
        self.assertEqual(found['source_inputs'][0], scheme)
        for changes in [dict(exit_code=1), dict(inputs_current=False), dict(finished_ns=101),
                        dict(outputs=[]), dict(outputs=[dict(output, sha256='other')]),
                        dict(outputs=[dict(output, bytes=30)]), dict(inputs=[scheme, scheme])]:
            with self.subTest(changes=changes):
                self.assertIsNone(generated_source_producer(helper, parent, [dict(producer, **changes)]))
        self.assertIsNone(generated_source_producer(helper, parent, [producer, dict(producer, pid=3)]))
        self.assertIsNone(generated_source_producer(helper, dict(parent, inputs=[]), [producer]))

    @unittest.skipUnless(shutil.which('gxi'), 'released Gerbil SDK required')
    def test_indexed_projection_matches_independent_list_membership(self):
        module = Path('t/harness/artifact-admission.ss').resolve()
        expression = f'''(import {json.dumps(str(module))})
(def selection '(#t ("suite.ss") ()))
(for-each (lambda (cached)
 (for-each (lambda (required)
  (let* ((record (list 'profile 'sources 'resources selection cached))
         (expected (and (andmap (lambda (m) (member m cached)) required) cached)))
   (unless (equal? (artifact-support-projection record selection required) expected)
    (error "indexed completeness changed" cached required))
   (when (artifact-support-projection record '(#f () ()) required)
    (error "wrong selection admitted"))))
  '(() ("a") ("b") ("a" "b") ("b" "a") ("a" "a"))))
 '(() ("a") ("b") ("a" "b") ("b" "a") ("a" "a")))
(display "PROJECTION-INDEX-CHECKED")'''
        result = subprocess.run(['gxi', '-:max-heap=1G,debug=q', '-e', expression],
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout, 'PROJECTION-INDEX-CHECKED')

    @unittest.skipUnless(shutil.which('gxi'), 'released Gerbil SDK required')
    def test_unchanged_cache_keeps_encoding_but_rechecks_resources(self):
        module = Path('t/harness/artifact-admission.ss').resolve()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            library = root / 'lib'
            library.mkdir()
            (library / 'fixture.ssi').write_text('original')
            expression = f'''(import {json.dumps(str(module))})
(def library {json.dumps(str(library))})
(def file {json.dumps(str(root / 'support.sexp'))})
(def sources (make-hash-table))
(hash-put! sources "fixture.ss" "digest")
(def (record previous)
 (artifact-record-support-cache! file sources library '() '(#t () ()) '("fixture") previous))
(record #f)
(def previous (artifact-support-cache file sources library '()))
(def inode (file-info-inode (file-info file)))
(record previous)
(unless (= inode (file-info-inode (file-info file))) (error "unchanged record encoded again"))
(call-with-output-file (path-expand "fixture.ssi" library) (lambda (out) (display "changed" out)))
(record previous)
(when (= inode (file-info-inode (file-info file))) (error "changed resource did not publish"))
(unless (artifact-support-cache file sources library '()) (error "fresh cache rejected"))
(display "CACHE-ENCODING-CHECKED")'''
            result = subprocess.run(['gxi', '-:max-heap=1G,debug=q', '-e', expression],
                                    cwd=root, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stdout.splitlines(), ['BUILD-TEST-LIBRARY support-cache-write=1',
                'BUILD-TEST-LIBRARY support-cache-write=0', 'BUILD-TEST-LIBRARY support-cache-write=1',
                'CACHE-ENCODING-CHECKED'])

    @unittest.skipUnless(shutil.which('gxi'), 'released Gerbil SDK required')
    def test_support_interfaces_reject_source_resource_profile_and_receipt_changes(self):
        module = Path('t/harness/artifact-admission.ss').resolve()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            library = root / 'lib'
            compiled = library / 'gerbil-ascent/reference.ssi'
            compiled.parent.mkdir(parents=True)
            compiled.write_text('compiled interface')
            record = root / 'support.sexp'
            expression = f'''(import {json.dumps(str(module))})
(def file {json.dumps(str(record))})
(def library {json.dumps(str(library))})
(def sources (make-hash-table))
(hash-put! sources "reference.ss" "source-digest")
(artifact-record-support-cache! file sources library '("profile") '(#t ("suite.ss") ()) '("reference"))
(def (read-support)
 (let (record (artifact-support-cache file sources library '("profile")))
  (if record (artifact-support-interfaces record library) [])))
(def current (artifact-support-cache file sources library '("profile")))
(unless (equal? (artifact-support-projection current '(#t ("suite.ss") ()) '("reference")) '("reference"))
 (error "complete matching projection not reused"))
(when (artifact-support-projection current '(#t ("suite.ss") ()) '("missing-dependency"))
 (error "incomplete cached projection reused"))
(for-each (lambda (selection)
 (when (artifact-support-projection current selection '("reference")) (error "different roots reused" selection)))
 '( (#f ("suite.ss") ()) (#t ("other.ss") ()) (#t ("suite.ss") ("consumer.ss")) ))
(unless (equal? (read-support) '("reference")) (error "current reference not reused"))
(def original-modules (car (cddddr current)))
(set-car! (cddddr current) (cons "../outside" original-modules))
(call-with-output-file file (lambda (out) (write current out)))
(unless (null? (read-support)) (error "foreign module catalog accepted"))
(set-car! (cddddr current) original-modules)
(call-with-output-file file (lambda (out) (write current out)))
(hash-put! sources "reference.ss" "changed-source")
(unless (null? (read-support)) (error "changed source reused"))
(hash-put! sources "reference.ss" "source-digest")
(when (artifact-support-cache file sources library '("other")) (error "wrong compiler profile reused"))
(call-with-output-file {json.dumps(str(compiled))} (lambda (out) (display "changed output" out)))
(unless (null? (read-support)) (error "changed compiled output reused"))
(call-with-output-file file (lambda (out) (display "(malformed)" out)))
(unless (null? (read-support)) (error "malformed receipt reused"))
(display "SUPPORT-CACHE-CHECKED")
'''
            process = subprocess.run(['gxi', '-:max-heap=1G,debug=q', '-e', expression],
                                     cwd=root, capture_output=True, text=True, timeout=30)
            self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
            self.assertIn('SUPPORT-CACHE-CHECKED', process.stdout)

    @unittest.skipUnless(shutil.which('gxi'), 'released Gerbil SDK required')
    def test_static_c_producer_is_observed_across_separate_gsc_jobs(self):
        from ascent_workbench.preparation_work import install, summarize
        import os
        sdk = Path(subprocess.check_output(['gxi', '-e', '(display (gerbil-home))'], text=True).strip())
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            source = root / 'producer.scm'
            source.write_text('(define (ascent-producer x) (+ x 1))\n')
            generated = root / 'producer.c'
            copied = root / 'renamed.c'
            observer = root / 'work'
            env = dict(os.environ, **install(observer, sdk / 'bin/gxi', sdk / 'bin/gsc'))
            for arguments in [['-c', '-o', str(generated), str(source)],
                              ['-obj', '-o', str(root / 'renamed.o'), str(copied)]]:
                if arguments[0] == '-obj':
                    shutil.copyfile(generated, copied)
                process = subprocess.run([str(observer / 'gsc'), *arguments], env=env, cwd=root,
                                         capture_output=True, text=True, timeout=30)
                self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
            (observer / 'gsc-records').rename(observer / 'build')
            phase = summarize(observer)['phases']['build']
            self.assertEqual(phase['generated_scheme_attributed_jobs'], 1)
            self.assertEqual(phase['generated_scheme_unattributed_cpu_seconds'], 0)
            cost, = phase['compiler_source_costs']
            self.assertEqual(cost['generated_scheme_input']['path'], str(source))
            self.assertEqual(cost['generated_source_producer']['generated_c_output']['path'], str(generated))
            self.assertGreater(cost['gcc_cumulative_ggc_bytes'], 0)
            self.assertGreater(cost['process_wall_ns'], 0)
            self.assertGreater(cost['max_child_rss_bytes'], 0)
            self.assertGreaterEqual(cost['major_faults'], 0)
            self.assertGreaterEqual(cost['input_blocks'], 0)
            self.assertGreaterEqual(cost['output_blocks'], 0)
            self.assertIsNone(phase['cumulative_allocation_bytes'])
            self.assertFalse(phase['cumulative_allocation_observed'])

    @unittest.skipUnless(shutil.which('gxi'), 'released Gerbil SDK required')
    def test_sdk_net_stack_counter_is_not_cumulative_allocation(self):
        import os
        sdk = Path(subprocess.check_output(['gxi', '-e', '(display (gerbil-home))'], text=True).strip())
        fixture = Path('workbench/tests/fixtures/allocation-stack.scm').read_bytes()
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'allocation-stack.scm'
            source.write_bytes(fixture)
            bundle = Path(folder) / 'allocation.o1'
            env = dict(os.environ, GAMBOPT=f'~~={sdk},~~bin={sdk}/bin,~~lib={sdk}/lib')
            compiled = subprocess.run([str(sdk / 'bin/gsc'), '-dynamic', '-o', str(bundle), str(source)],
                                      env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            process = subprocess.run(['gxi', '-:max-heap=1G,debug=q', '-e', f'(load {json.dumps(str(bundle))})'],
                                     capture_output=True, text=True, timeout=30)
            self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
            before, after, gcs, result = map(float, process.stdout.strip().strip('()').split())
            self.assertEqual(result, 200010000)
            self.assertEqual(gcs, 0, process.stdout)
            self.assertLess(after, before, process.stdout)
            # This is an observed counterexample, never an allocation benefit.

    @unittest.skipUnless(shutil.which('gxi'), 'released Gerbil SDK required')
    def test_linker_emitted_modules_and_multi_input_link_source_keep_one_cost_node(self):
        from ascent_workbench.preparation_work import install, summarize
        import os
        sdk = Path(subprocess.check_output(['gxi', '-e', '(display (gerbil-home))'], text=True).strip())
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            for name in ('ready', 'first', 'second'):
                (root / f'{name}.scm').write_text(f'(define ({name}-value x) (+ x 1))\n')
            observer = root / 'work'
            env = dict(os.environ, **install(observer, sdk / 'bin/gxi', sdk / 'bin/gsc'))
            commands = [['-c', '-o', 'ready.c', 'ready.scm'],
                        ['-link', '-target', 'C', str(root / 'ready.c'), str(root / 'first.scm'), str(root / 'second.scm')]]
            commands += [['-obj', '-o', str(root / f'{name}.o'), str(root / f'{name}.c')]
                         for name in ('first', 'second', 'second_')]
            commands += [['-link', '-target', 'C', str(root / 'ready.c'), str(root / 'first.scm'), str(root / 'second.scm')],
                         ['-obj', '-o', str(root / 'first-again.o'), str(root / 'first.c')]]
            for arguments in commands:
                process = subprocess.run([str(observer / 'gsc'), *arguments], env=env, cwd=root,
                                         capture_output=True, text=True, timeout=30)
                self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
            (observer / 'gsc-records').rename(observer / 'build')
            phase = summarize(observer)['phases']['build']
            self.assertEqual(phase['source_attributed_jobs'], 4)
            self.assertTrue(phase['source_cost_complete'])
            self.assertEqual(phase['generated_scheme_attributed_jobs'], 3)
            link, = [row for row in phase['compiler_source_costs']
                     if row['generated_source_producer']['operation'] == 'link-source']
            self.assertEqual({Path(row['path']).name for row in link['source_inputs']},
                             {'ready.c', 'first.c', 'second.c'})
            self.assertEqual(len(phase['compiler_source_costs']), 4)
            first = [row for row in phase['compiler_source_costs'] if Path(row['actual_c_inputs'][0]['path']).name == 'first.c']
            self.assertEqual(len({row['generated_source_producer']['producer_pid'] for row in first}), 2)
            self.assertTrue(phase['gcc_cumulative_ggc_observed'])
            self.assertGreater(link['gcc_cumulative_ggc_bytes'], 0)

    def test_output_roles_require_c_target_compiler_origin_and_disjoint_outputs(self):
        scheme = {'path': '/compiler/input.scm'}
        self.assertEqual(compiler_output_paths(['-c', '-o', 'output.c'], [scheme], '/compiler'),
                         [Path('/compiler/output.c')])
        self.assertEqual(compiler_output_paths(['-c', '-o', 'output.c'], [scheme]), [])
        for arguments in [['-c', '-o', '/compiler/output.c', '-target', 'JavaScript'],
                          ['-link', '-flat'], ['-link', '-o', '/compiler/input.c']]:
            with self.subTest(arguments=arguments):
                self.assertEqual(compiler_output_paths(arguments, [scheme]), [])
        self.assertEqual(compiler_output_paths(['-link'], [scheme, {'path': '/compiler/input.c'}]), [])

    def test_link_input_edges_do_not_multiply_native_job_allocation(self):
        jobs = [{'gcc_ggc_bytes': 11, 'source_inputs': ['a.c', 'b.c', 'c.c']},
                {'gcc_ggc_bytes': 7, 'source_inputs': []}]
        self.assertEqual(compiler_allocation_total(jobs), 18)

    def test_only_identical_program_work_audit_can_omit_comparison_controls(self):
        import runpy
        order = runpy.run_path('tools/ci/build-cost-control.py')['control_order']
        self.assertEqual(order(True, 'same', 'same'), ['candidate'])
        for work, a, b in [(False, 'same', 'same'), (False, 'a', 'b'), (True, 'a', 'b')]:
            self.assertEqual(order(work, a, b), ['baseline', 'candidate', 'candidate', 'baseline'])

    def test_overlapping_same_path_publishers_are_not_attributed(self):
        source = {'path': '/build/module.scm', 'sha256': 'scheme', 'bytes': 1}
        output = {'path': '/build/module.c', 'sha256': 'c', 'bytes': 2}
        helper = {'parent_gsc_observer': '9', 'inputs': [output], 'compiler_input_paths': [output['path']]}
        parent = {'pid': 9, 'started_ns': 100, 'inputs': [output]}
        def producer(pid, start, end):
            return {'pid': pid, 'started_ns': start, 'finished_ns': end, 'exit_code': 0, 'inputs_current': True,
                    'arguments': ['-c', '-o', output['path'], source['path']], 'inputs': [source], 'outputs': [output]}
        self.assertIsNone(generated_source_producer(helper, parent, [producer(1,10,30), producer(2,20,40)]))
        result = generated_source_producer(helper, parent, [producer(1,10,30), producer(2,31,40)])
        self.assertEqual(result['producer_pid'], 2)

    def test_missing_source_cost_never_qualifies_complete_compiler_work(self):
        self.assertTrue(source_cost_coverage(0, 0))
        self.assertTrue(source_cost_coverage(360, 360))
        self.assertFalse(source_cost_coverage(360, 340))

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

    def test_pass_costs_keep_hierarchy_and_total_without_adding_overlap(self):
        source = Path('/tmp/owner.c').resolve()
        report = self.report(source)
        timers = report['runs'][0]['invocations'][0]['properties']['gcc/timeReport']['timevars']
        for item, wall in zip(timers, [2.0, 3.0, 4.0]):
            item['elapsed']['wall'] = wall
        timers[0]['children'] = [{'name': 'TOTAL', 'elapsed': {'wall': 1, 'ggc_mem': 150}}]
        result = gcc_pass_costs(report, source)
        self.assertEqual(result['total'], {'path': ['TOTAL'], 'wall_seconds': 4.0, 'ggc_bytes': 400})
        self.assertEqual(result['inclusive_passes'][1]['path'], ['phase parsing', 'TOTAL'])
        self.assertEqual(len(result['inclusive_passes']), 4)
        self.assertNotIn('helper_cpu_seconds', result)
        for bad in [None, True, -1, float('nan'), float('inf'), '1.0']:
            invalid = copy.deepcopy(report)
            invalid['runs'][0]['invocations'][0]['properties']['gcc/timeReport']['timevars'][0]['elapsed']['wall'] = bad
            with self.subTest(wall=bad), self.assertRaisesRegex(ValueError, 'pass wall'):
                gcc_pass_costs(invalid, source)
        timers.append(copy.deepcopy(timers[0]))
        with self.assertRaisesRegex(ValueError, 'duplicate GCC pass'):
            gcc_pass_costs(report, source)
        with self.assertRaisesRegex(ValueError, 'attribution'):
            gcc_pass_costs(self.report(source), source.with_name('foreign.c'))

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
            options = '-DASCENT_PROFILE_MARKER=17 -fno-tree-dominator-opts'
            env.update(BUILD_DYN_CC_OPTIONS_PARAM=options, GAMBITDIR_INCLUDE=str(sdk / 'include'), GAMBITDIR_LIB=str(sdk / 'lib'),
                       BUILD_DYN_INPUT_FILENAMES_PARAM=source.name, BUILD_DYN_META_INFO_FILE_PARAM=source.name,
                       BUILD_DYN_OUTPUT_FILENAME_PARAM=str(root / 'owned.o1'))
            process = subprocess.run([str(observer / 'gambuild-C'), 'dyn'], env=env,
                                     capture_output=True, text=True, timeout=30, cwd=root)
            self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
            (observer / 'gsc-records').rename(observer / 'prepare')
            phase = summarize(observer)['phases']['prepare']
            self.assertTrue(phase['compiler_options_observed'])
            self.assertEqual(phase['compiler_source_costs'][0]['requested_cc_options'], options)
            self.assertTrue(phase['gcc_cumulative_ggc_observed'])
            self.assertGreater(phase['gcc_cumulative_ggc_bytes'], 0)
            self.assertFalse(phase['cumulative_allocation_observed'])
            record_path, = (observer / 'prepare').glob('*.json')
            record = json.loads(record_path.read_text())
            self.assertEqual(record['requested_cc_options'], options)
            self.assertIn('-ftime-report', record['effective_cc_options'])
            report_path = observer / 'inputs' / record['gcc_report']['sha256']
            report_path.write_text('{}')
            with self.assertRaisesRegex(ValueError, 'damaged GCC allocation report'):
                summarize(observer)
