# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Release-native reference-interface and source-root projection integration."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(shutil.which('gxi'), 'released Gerbil SDK required')
class ReferenceCacheTests(unittest.TestCase):
    def test_incremental_restore_reuses_reference_objects_and_updates_changed_dependency(self):
        import time
        from ascent_workbench.preparation_work import install
        with tempfile.TemporaryDirectory() as folder:
            area = Path(folder).resolve()
            root, cache = area / 'repo', area / 'sources'
            root.mkdir()
            cache.mkdir()
            def git(*arguments):
                return subprocess.check_output(['git', '-C', str(root), *arguments], text=True)
            git('init', '-q')
            git('config', 'user.name', 'Cache test')
            git('config', 'user.email', 'cache-test@example.invalid')
            (root / '.gitignore').write_text('.gerbil/\n')
            (root / 'gerbil.pkg').write_text('(package: gerbil-ascent)\n')
            (root / 'core.ss').write_text('(export number)\n(def (number) 41)\n')
            (root / 'reference.ss').write_text('(export answer)\n(def answer 7)\n')
            (root / 'consumer.ss').write_text('(import "core" "reference")\n(export read-value)\n(def (read-value) (list (number) answer))\n')
            (root / 'deleted-test.ss').write_text('(export)\n')
            git('add', '.gitignore', 'gerbil.pkg', 'core.ss', 'reference.ss', 'consumer.ss', 'deleted-test.ss')
            git('commit', '-qm', 'seed')
            library = root / '.gerbil/lib'
            library.mkdir(parents=True)
            expression = f'''(import :std/make)
(make '("core" "reference" "consumer") srcdir: {json.dumps(str(root))}
 libdir: {json.dumps(str(library))} prefix: "gerbil-ascent" optimize: #t parallelize: 3)
'''
            sdk = Path(subprocess.check_output(['gxi', '-e', '(display (gerbil-home))'], text=True).strip())
            observer = area / 'compiler-work'
            env = dict(os.environ, **{key: value for key, value in install(observer, sdk / 'bin/gxi', sdk / 'bin/gsc').items()
                                      if key != 'PATH'})
            def make():
                result = subprocess.run(['gxi', '-:max-heap=1G,debug=q', '-e', expression],
                                        cwd=root, env=env, capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            make()
            def resources():
                return {str(p.relative_to(library)): (p.read_bytes(), p.stat().st_mtime_ns)
                        for p in library.rglob('*') if p.is_file() and 'reference' in p.name}
            before = resources()
            self.assertTrue(before)
            for source in root.glob('*.ss'):
                shutil.copy2(source, cache / source.name)
            source_clock = (root / 'reference.ss').stat().st_mtime_ns
            # Separate actual filesystem timestamps; no fabricated future clock.
            time.sleep(1.05)
            (root / 'core.ss').write_text('(export number)\n(def (number) 43)\n')
            (root / 'deleted-test.ss').unlink()
            (root / 'new-test.ss').write_text('(export)\n')
            git('add', '-A', '--', '*.ss')
            git('commit', '-qm', 'current program')
            os.utime(root / 'reference.ss', None)  # Fresh checkout would make it stale.
            for source in cache.glob('*.ss'):
                shutil.copy2(source, root / source.name)
            self.assertIn('41', (root / 'core.ss').read_text())
            workflow = Path('.github/workflows/build-cost.yml').read_text()
            commands = workflow.split('          # BEGIN GENERATED PREPARATION RESTORE-INPUTS\n')[1].split(
                '          # END GENERATED PREPARATION RESTORE-INPUTS')[0]
            subprocess.run(['bash', '-euc', commands], cwd=root, check=True, capture_output=True, text=True)
            self.assertEqual(git('diff', '--name-only', 'HEAD').strip(), '')
            self.assertFalse((root / 'deleted-test.ss').exists())
            self.assertTrue((root / 'new-test.ss').is_file())
            self.assertIn('43', (root / 'core.ss').read_text())
            self.assertEqual((root / 'reference.ss').stat().st_mtime_ns, source_clock)
            (observer / 'gsc-records').rename(observer / 'seed-records')
            current_work = observer / 'current-records'
            current_work.mkdir()
            env['ASCENT_GSC_WORK_DIRECTORY'] = str(current_work)
            make()
            work = [json.loads(record.read_text()) for record in current_work.glob('*.json')]
            self.assertTrue(work, 'changed producer did not invoke the compiler')
            self.assertFalse(any('reference' in Path(item['path']).name for record in work for item in record['inputs']),
                             'unchanged reference reached a GSC or native helper job')
            self.assertEqual(resources(), before, 'unchanged reference was recompiled')
            invoke = f'(add-load-path! {json.dumps(str(library))}) (import :gerbil-ascent/consumer) (write (read-value))'
            result = subprocess.run(['gxi', '-:max-heap=1G,debug=q', '-e', invoke],
                                    cwd=root, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stdout.strip(), '(43 7)')

    def test_cached_reference_and_source_consumer_keep_complete_native_closure(self):
        hook = Path('t/harness/library-spec.ss').resolve()
        env = dict(os.environ, GERBIL_PATH=os.environ.get('GERBIL_PATH', str(Path('.gerbil').resolve())))
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            library = root / 'lib'
            library.mkdir()
            (root / 'gerbil.pkg').write_text('(package: gerbil-ascent)\n')
            (root / 'reference.ss').write_text('(export answer)\n(def answer 42)\n')
            (root / 'consumer.ss').write_text('(import "reference")\n(export result)\n(def result answer)\n')
            compile_expression = f'''(import :std/make)
(make '("reference") srcdir: {json.dumps(str(root))} libdir: {json.dumps(str(library))}
      prefix: "gerbil-ascent" optimize: #t parallelize: 3)
'''
            compiled = subprocess.run(['gxi', '-:max-heap=1G,debug=q', '-e', compile_expression],
                                      cwd=root, capture_output=True, text=True, timeout=30)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            expression = f'''(import :gerbil/expander
 :asp-gerbil-scheme/src/build-api/native-import-closure {json.dumps(str(hook))})
(def root {json.dumps(str(root))})
(def library {json.dumps(str(library))})
(add-load-path! library)
(add-load-path! root)
(call-with-preparation-production-interfaces #t library '("reference")
 (lambda () (import-module "reference.ss" #f #f) (import-module "consumer.ss" #f #f)))
(when (with-catch (lambda (_) #f)
        (lambda () (call-with-asp-gerbil-scheme-prepared-source-graph
          (lambda () (asp-gerbil-scheme-prepared-native-import-closure root '("reference" "consumer"))))))
 (error "interface-path root unexpectedly admitted as a prepared source-path root"))
(def closure
 (call-with-preparation-production-interfaces #t library '("reference")
  (lambda () (asp-gerbil-scheme-native-import-closure root '("reference" "consumer")))))
(unless (and (= (length closure) 2) (member "reference.ss" closure) (member "consumer.ss" closure))
 (error "incomplete reference/source closure" closure))
(display "REFERENCE-SOURCE-CLOSURE-CHECKED")
'''
            invoked = subprocess.run(['gxi', '-:max-heap=1G,debug=q', '-e', expression],
                                     cwd=root, env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(invoked.returncode, 0, invoked.stdout + invoked.stderr)
            self.assertIn('REFERENCE-SOURCE-CLOSURE-CHECKED', invoked.stdout)
