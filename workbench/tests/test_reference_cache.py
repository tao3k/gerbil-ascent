# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Release-native reference-interface and source-root projection integration."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(shutil.which('gxi'), 'released Gerbil SDK required')
class ReferenceCacheTests(unittest.TestCase):
    def test_cached_reference_and_source_consumer_keep_complete_native_closure(self):
        hook = Path('t/harness/library-spec.ss').resolve()
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
                                     cwd=root, capture_output=True, text=True, timeout=30)
            self.assertEqual(invoked.returncode, 0, invoked.stdout + invoked.stderr)
            self.assertIn('REFERENCE-SOURCE-CLOSURE-CHECKED', invoked.stdout)
