# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Release-native compiler-profile admission for frozen performance references."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


@unittest.skipUnless(shutil.which('gxi'), 'released Gerbil SDK required')
class StudyProfileTests(unittest.TestCase):
    def test_reference_uses_production_profile_and_native_metadata_invalidation(self):
        project = Path.cwd().resolve()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            (root / 'gerbil.pkg').write_text('(package: gerbil-ascent)\n')
            (root / 'justfile').write_text('# isolated build fixture\n')
            (root / '.cache/ascent/compiled-library').mkdir(parents=True)
            for path in ['build-modules.ss', 't/performance/run.ss']:
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(';; previous build profile\n')
            modules = ['core/relation-view', 't/performance/profile-reference']
            for name in modules:
                path = root / (name + '.ss')
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('''(import :std/ffi) (C-ffi-macrology) (export limit)
(C-declare "#ifndef ___SINGLE_HOST_LIMIT\\n#define ___SINGLE_HOST_LIMIT 0\\n#endif")
(def-C-lambda (limit) => int "___return(___SINGLE_HOST_LIMIT);")
''')
            library = root / '.gerbil/lib'
            library.mkdir(parents=True)
            env = dict(os.environ, GERBIL_PATH=os.environ.get('GERBIL_PATH', str(project / '.gerbil')),
                       GERBIL_LOADPATH=str(project) + (':' + os.environ['GERBIL_LOADPATH'] if os.environ.get('GERBIL_LOADPATH') else ''))
            def invoke(expression):
                result = subprocess.run(['gxi', '-:max-heap=1G,debug=q', '-e', expression],
                                        cwd=root, env=env, capture_output=True, text=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return result.stdout
            invoke(f'''(import :std/make
 (only-in {json.dumps(str(project / 'build-modules.ss'))} gerbil-ascent-compiler-options))
(make (list (append '(gxc: "core/relation-view") gerbil-ascent-compiler-options)
        "t/performance/profile-reference") srcdir: {json.dumps(str(root))}
 libdir: {json.dumps(str(library))} optimize: #t parallelize: 3)
''')
            query = f'''(add-load-path! {json.dumps(str(library))})
(import (prefix-in :gerbil-ascent/core/relation-view a-)
        (prefix-in :gerbil-ascent/t/performance/profile-reference b-))
(write (list (a-limit) (b-limit))) (newline)'''
            self.assertEqual(invoke(query).strip(), '(512 0)')
            def resources(module):
                stem = module.split('/')[-1]
                return {str(p.relative_to(library)): (p.read_bytes(), p.stat().st_mtime_ns)
                        for p in library.rglob('*') if p.is_file() and stem in p.name}
            production_before = resources('core/relation-view')
            time.sleep(1.05)
            (root / 't/performance/run.ss').write_text(';; current matched build profile\n')
            expression = f'''(add-load-path! {json.dumps(str(library))})
(import {json.dumps(str(project / 't/performance/run.ss'))}
        {json.dumps(str(project / 't/performance/studies.ss'))})
(build-study! (make-study 'profile-check '("core/relation-view" "t/performance/profile-reference")
 "unused" '() #f '() #f ".ss") {json.dumps(str(library))} "unused")'''
            invoke(expression)
            self.assertEqual(invoke(query).strip(), '(512 512)')
            self.assertEqual(resources('core/relation-view'), production_before)
            reference_before = resources('t/performance/profile-reference')
            invoke(expression)
            self.assertEqual(resources('t/performance/profile-reference'), reference_before)
