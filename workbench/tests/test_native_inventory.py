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
    def test_original_matrix_has_every_file_and_selected_api_controls(self):
        tasks = inventory(ROOT / "workbench/engine_tests")
        abi = [path.name for backend, path in tasks if backend == "abi"]
        api = [path.name for backend, path in tasks if backend == "api"]
        self.assertEqual(len(abi), 33)
        self.assertEqual(len(set(abi)), 33)
        self.assertEqual(api, list(API_FILES))
        self.assertEqual(len(tasks), 40)

    def test_missing_selected_backend_control_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            for name in API_FILES[:-1]:
                (directory / name).touch()
            with self.assertRaisesRegex(ValueError, "incomplete"):
                inventory(directory)

    def test_source_resource_and_backend_identity_changes_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            library = root / "bundle/libascent.so"
            resource = library.parent / "syntax/module.o1"
            extension = root / "api/_ascent_cffi.so"
            source = root / "program.ss"
            for path in (library, resource, extension, source, root / "justfile", root / ".github/workflows/ci.yml"):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"original")
            sha = hashlib.sha256(b"original").hexdigest()
            producer = {"sourceRoot": str(root), "sourceInputs": {"program.ss": sha},
                        "librarySha256": sha, "syntaxResources": {"module.o1": {"sha256": sha}}}
            library.with_suffix(".so.json").write_text(json.dumps(producer))
            api = {"producerBuild": producer, "extensionSha256": sha,
                   "library": "libascent.so", "librarySha256": sha}
            (extension.parent / api["library"]).write_bytes(b"original")
            api_sidecar = extension.parent / "receipt.json"
            api_sidecar.write_text(json.dumps(api))
            with patch("ascent_workbench.native_tests.ROOT", root), \
                 patch.dict(os.environ, ASCENT_ENGINE_LIBRARY=str(library)), \
                 patch("ascent_workbench.native_tests.importlib.util.find_spec", return_value=SimpleNamespace(origin=str(extension))):
                self.assertIn(str(resource), qualification_inputs([]))
                for changed in (source, resource, extension):
                    changed.write_bytes(b"modified")
                    with self.assertRaisesRegex(ValueError, "input drift"):
                        qualification_inputs([])
                    changed.write_bytes(b"original")
                api["producerBuild"] = {"sourceInputs": {"program.ss": "other-producer"}}
                api_sidecar.write_text(json.dumps(api))
                with self.assertRaisesRegex(ValueError, "producer sources differ"):
                    qualification_inputs([])


if __name__ == "__main__":
    unittest.main()
