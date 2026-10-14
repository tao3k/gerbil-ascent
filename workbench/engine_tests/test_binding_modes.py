# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Run in a fresh process for each backend; requires a real AOT engine."""
import os
import signal
import subprocess
import sys
import threading
import unittest

from ascent import Engine, EngineError


class BindingContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.backend = os.environ.get("ASCENT_ENGINE_BACKEND", "abi")
        before = signal.getsignal(signal.SIGCHLD)
        cls.engine = Engine(None if cls.backend == "api" else os.environ["ASCENT_ENGINE_LIBRARY"])
        if cls.engine.backend != cls.backend:
            raise AssertionError("wrong binding backend")
        if signal.getsignal(signal.SIGCHLD) != before:
            raise AssertionError("engine changed host child-reaping policy")

    @classmethod
    def tearDownClass(cls):
        cls.engine.shutdown()
        if cls.engine.lib.ascent_runtime_init() != -2:
            raise AssertionError("shutdown is not terminal")

    def test_result_memory_is_released_on_c_errors(self):
        ffi, lib = self.engine.ffi, self.engine.lib
        for payload in (b"", b"{}\0", b"\xff"):
            result = ffi.new("ascent_result *")
            try:
                self.assertEqual(lib.ascent_request(payload, len(payload), result), -4)
            finally:
                lib.ascent_result_release(result)
            self.assertEqual(result.payload, ffi.NULL)
            self.assertEqual(result.length, 0)

    def test_typed_error_does_not_poison_next_request(self):
        with self.assertRaises(EngineError):
            self.engine.request({"operation": "unknown"})
        self.assertEqual(self.engine.request({"operation": "describe"})["abi"], 1)

    def test_backend_switch_rejects_before_loading_another_runtime(self):
        with self.assertRaisesRegex(EngineError, "one binding backend"):
            Engine("not-a-library" if self.backend == "api" else None)

    def test_wrong_os_thread_is_rejected(self):
        statuses = []
        def run():
            try:
                self.engine.request({"operation": "describe"})
            except EngineError as error:
                statuses.append(error.status)
        thread = threading.Thread(target=run)
        thread.start()
        thread.join(timeout=5)
        self.assertFalse(thread.is_alive())
        self.assertEqual(statuses, [-3])

    def test_host_observes_child_failure(self):
        result = subprocess.run([sys.executable, "-c", "raise SystemExit(7)"], timeout=5)
        self.assertEqual(result.returncode, 7)

    def test_fork_child_cannot_enter_or_clean_up_inherited_runtime(self):
        pid = os.fork()
        if pid == 0:
            try:
                for action in (lambda: self.engine.request({"operation": "describe"}),
                               self.engine.shutdown,
                               lambda: Engine(None if self.backend == "api" else os.environ["ASCENT_ENGINE_LIBRARY"])):
                    try:
                        action()
                    except EngineError as error:
                        if error.status != -2:
                            os._exit(2)
                    else:
                        os._exit(3)
                from ascent import _shutdown
                _shutdown()  # inherited atexit cleanup must not enter Scheme
                os._exit(0)
            except BaseException:
                os._exit(4)
        _, status = os.waitpid(pid, 0)
        self.assertEqual(os.waitstatus_to_exitcode(status), 0)
        self.assertEqual(self.engine.request({"operation": "describe"})["abi"], 1)

    def test_session_exception_releases_handle(self):
        program = {"relations": [{"name": "Source", "columns": [{"kind": "symbol"}],
                                   "source": True, "rows": [["value"]]}],
                   "rules": [], "queries": ["Source"]}
        with self.assertRaisesRegex(RuntimeError, "host-error"):
            with self.engine.open(program) as session:
                first = session.run()
                self.assertTrue(first["complete"])
                first["relations"]["Source"].clear()
                self.assertEqual(session.run()["relations"]["Source"], [["value"]])
                raise RuntimeError("host-error")
        with self.assertRaises(EngineError):
            session.run()


if __name__ == "__main__":
    unittest.main()
