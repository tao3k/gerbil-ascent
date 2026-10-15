# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Preserve the complete downstream backend matrix after moving projects."""
from pathlib import Path
import hashlib
import json
import os
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from ascent_workbench.native_tests import API_FILES, ROOT, inventory, qualification_inputs


class NativeInventory(unittest.TestCase):
    def test_unittest_warnings_do_not_hide_outcomes_or_admit_missing_results(self):
        import runpy
        parse=runpy.run_path(str(ROOT/'workbench/engine_tests/run_suite.py'))['parse_outcomes']
        text=("test_fork (module.Contract.test_fork) ... warning: fork\n"
              "  pid = os.fork()\n"
              "ok\n"
              "test_failure (module.Contract.test_failure) ... FAIL\n"
              "test_missing (module.Contract.test_missing) ... ")
        self.assertEqual(parse(text),{'module.Contract.test_fork':'ok',
                                     'module.Contract.test_failure':'FAIL'})

    def test_original_matrix_has_every_file_and_selected_api_controls(self):
        tasks = inventory(ROOT / "workbench/engine_tests")
        bindings = [path.name for backend,path in tasks if backend == 'pyo3']
        self.assertEqual(len(bindings),34)
        self.assertEqual(len(set(bindings)),34)
        self.assertTrue(set(API_FILES)<=set(bindings))
        self.assertEqual(len(tasks),34)

    def test_missing_selected_backend_control_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            for name in API_FILES[:-1]:
                (directory / name).touch()
            with self.assertRaisesRegex(ValueError, "incomplete"):
                inventory(directory)

    def test_source_resource_and_backend_identity_changes_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder).resolve()
            source=root/'program.ss'
            resource=root/'syntax/module.o1'
            extension=root/'api/_core.so'
            for path in (source,resource,extension,root/'justfile',root/'.github/workflows/ci.yml'):
                path.parent.mkdir(parents=True,exist_ok=True)
                path.write_bytes(b'original')
            sha=hashlib.sha256(b'original').hexdigest()
            receipt={'schema':'ascent.rust-build.v1','sourceInputs':{'program.ss':sha},'runtimeInputs':{str(resource):sha}}
            with patch('ascent_workbench.native_tests.ROOT',root), \
                 patch('ascent_workbench.native_tests.compiled_inputs',return_value=receipt), \
                 patch('ascent_workbench.native_tests.importlib.util.find_spec',return_value=SimpleNamespace(origin=str(extension))):
                self.assertIn(str(resource),qualification_inputs([]))
                for changed in (source,resource):
                    changed.write_bytes(b'modified')
                    with self.assertRaisesRegex(ValueError,'input drift'): qualification_inputs([])
                    changed.write_bytes(b'original')
                before=qualification_inputs([])
                extension.write_bytes(b'modified')
                self.assertNotEqual(before[str(extension)],qualification_inputs([])[str(extension)])
                receipt['sourceInputs']['program.ss']='other-producer'
                with self.assertRaisesRegex(ValueError,'input drift'): qualification_inputs([])

if __name__=='__main__': unittest.main()
