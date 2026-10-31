# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Delegate build dispatch to the SDK and retain its real flag expansion."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


BUILD_FLAGS = ("GERBIL_BUILD_RELEASE", "GERBIL_BUILD_OPTIMIZED", "GERBIL_BUILD_DEBUG")


@unittest.skipUnless(shutil.which("just"), "just is required")
class BuildDriverRouting(unittest.TestCase):
    def test_sdk_entrypoint_receives_package_prefix_cores_and_build_environment(self):
        repo = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prefix = root / "package"
            executable = root / "bin/gerbil"
            executable.parent.mkdir(parents=True)
            result = root / "arguments.json"
            executable.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "from pathlib import Path\n"
                "Path(os.environ['ASCENT_DRIVER_TEST_ARGUMENTS']).write_text("
                "json.dumps({'arguments': sys.argv[1:], "
                "'prefix': os.environ['GERBIL_PATH'], "
                "'cores': os.environ['GERBIL_BUILD_CORES'], "
                "'flags': {key: os.environ.get(key) for key in "
                f"{BUILD_FLAGS!r}" "}}))\n"
            )
            executable.chmod(0o755)
            environment = dict(os.environ, GERBIL_PATH=str(prefix),
                               GERBIL_BUILD_CORES="8",
                               PATH=str(executable.parent) + os.pathsep + os.environ["PATH"],
                               ASCENT_DRIVER_TEST_ARGUMENTS=str(result))
            for key in BUILD_FLAGS:
                environment.pop(key, None)
            for enabled in (False, True):
                with self.subTest(flags_enabled=enabled):
                    if enabled:
                        environment.update(dict.fromkeys(BUILD_FLAGS, ""))
                    child = subprocess.run(["just", "build"], cwd=repo, env=environment,
                                           capture_output=True, text=True, timeout=15)
                    self.assertEqual(child.returncode, 0, child.stdout + child.stderr)
                    observed = json.loads(result.read_text())
                    self.assertEqual(observed["arguments"], ["build"])
                    self.assertEqual(observed["prefix"], str(prefix))
                    self.assertEqual(observed["cores"], "8")
                    self.assertEqual(observed["flags"],
                                     dict.fromkeys(BUILD_FLAGS, "" if enabled else None))

    @unittest.skipUnless(shutil.which("gerbil"), "released Gerbil SDK required")
    def test_real_sdk_expands_build_flags_and_preserves_prefix_and_cores(self):
        repo = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prefix = root / ".gerbil"
            (root / "gerbil.pkg").write_text("(package: build-driver-check)\n")
            script = root / "build.ss"
            script.write_text(
                "#!/usr/bin/env gxi\n"
                "(def (main . args)\n"
                '  (displayln "DRIVER-ARGS " args)\n'
                '  (displayln "DRIVER-PREFIX " (getenv "GERBIL_PATH"))\n'
                '  (displayln "DRIVER-CORES " (getenv "GERBIL_BUILD_CORES")))\n'
            )
            script.chmod(0o755)
            environment = dict(os.environ, GERBIL_PATH=str(prefix), GERBIL_BUILD_CORES="8")
            for key in BUILD_FLAGS:
                environment.pop(key, None)
            for flag_value in (None, "", "t"):
                with self.subTest(flag_value=flag_value):
                    if flag_value is not None:
                        environment.update(dict.fromkeys(BUILD_FLAGS, flag_value))
                    child = subprocess.run(
                        ["just", "--justfile", str(repo / "justfile"),
                         "--working-directory", str(root), "build"],
                        cwd=root, env=environment, capture_output=True, text=True, timeout=15)
                    self.assertEqual(child.returncode, 0, child.stdout + child.stderr)
                    lines = child.stdout.splitlines()
                    # The released SDK owns ordering, rather than the Just wrapper.
                    args = "compile" + (" --debug --optimized --release" if flag_value is not None else "")
                    self.assertIn(f"DRIVER-ARGS ({args})", lines)
                    self.assertIn(f"DRIVER-PREFIX {prefix}", lines)
                    self.assertIn("DRIVER-CORES 8", lines)
