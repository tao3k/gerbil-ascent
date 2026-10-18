# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""The local build recipe preserves the upstream script environment and flags."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(shutil.which("just"), "just is required")
class BuildDriverRouting(unittest.TestCase):
    def test_standard_script_receives_package_prefix_cores_and_build_flags(self):
        repo = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory) / "package"
            executable = prefix / "bin/gxi"
            executable.parent.mkdir(parents=True)
            result = Path(directory) / "arguments.json"
            # Test-only executable records the actual child invocation. No
            # compiler or package-management process is started by this test.
            executable.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "from pathlib import Path\n"
                "Path(os.environ['ASCENT_DRIVER_TEST_ARGUMENTS']).write_text("
                "json.dumps({'arguments': sys.argv[1:], "
                "'prefix': os.environ['GERBIL_PATH'], "
                "'cores': os.environ['GERBIL_BUILD_CORES']}))\n"
            )
            executable.chmod(0o755)
            environment = dict(os.environ, GERBIL_PATH=str(prefix),
                               GERBIL_BUILD_CORES="8",
                               ASCENT_DRIVER_TEST_ARGUMENTS=str(result))
            flags = ("GERBIL_BUILD_RELEASE", "GERBIL_BUILD_OPTIMIZED",
                     "GERBIL_BUILD_DEBUG")
            for key in flags:
                environment.pop(key, None)
            for enabled in (False, True):
                with self.subTest(flags_enabled=enabled):
                    if enabled:
                        # gxpkg tests presence, including an empty value.
                        environment.update(dict.fromkeys(flags, ""))
                    subprocess.run(["just", "build"], cwd=repo, env=environment,
                                   capture_output=True, text=True,
                                   check=True, timeout=15)
                    observed = json.loads(result.read_text())
                    expected = ["build.ss", "compile"]
                    if enabled:
                        expected += ["--release", "--optimized", "--debug"]
                    self.assertEqual(observed["arguments"], expected)
                    self.assertEqual(observed["prefix"], str(prefix))
                    self.assertEqual(observed["cores"], "8")
