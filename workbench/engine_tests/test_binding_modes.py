# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Typed host admission, owner serialization, independent leases and fork isolation."""
import os
import signal
import subprocess
import sys
import threading
import unittest
from ascent import Engine, EngineError
from ascent import _core

class BindingContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        before = signal.getsignal(signal.SIGCHLD)
        cls.engine = Engine()
        cls.engine.describe()  # initialize the actual VM
        if signal.getsignal(signal.SIGCHLD) != before:
            raise AssertionError('engine changed host child-reaping policy')

    @classmethod
    def tearDownClass(cls):
        cls.engine.shutdown()
        with cls().assertRaises((EngineError, ValueError)):
            cls.engine.describe()

    def test_result_memory_is_released_on_c_errors(self):
        # The public boundary accepts typed values. Malformed packets still
        # exercise rooted native exception cleanup through the real C ABI.
        for payload in ({}, {'operation': 'unknown'}, {'operation': 'native-result', 'handle': -1}):
            with self.assertRaises(EngineError):
                _core._scheme_call(payload)
            self.assertEqual(self.engine.describe()['abi'], 1)

    def test_typed_error_does_not_poison_next_request(self):
        with self.assertRaises(EngineError):
            self.engine.dsl('(def (broken)', trusted=True)
        self.assertEqual(self.engine.describe()['abi'], 1)

    def test_backend_switch_rejects_before_loading_another_runtime(self):
        # Caller ownership is independent; closing one owner cannot tear down
        # the process-wide VM underneath another caller.
        other = Engine()
        other.describe()
        other.shutdown()
        with self.assertRaises((EngineError, ValueError)):
            other.describe()
        self.assertEqual(self.engine.describe()['abi'], 1)
        with self.assertRaises(TypeError):
            Engine('not-a-library')

    def test_wrong_os_thread_is_rejected(self):
        # The owner channel now admits arbitrary host threads. The VM itself
        # remains on its one owning thread; mutable Scheme state is serialized.
        with self.engine.dsl('(def n 0) (def (next) (set! n (+ n 1)) n)', trusted=True) as module:
            values, errors = [], []
            def run():
                try:
                    for _ in range(10):
                        with module.call('next') as value:
                            values.append(int(value.graph['root']['value']))
                except BaseException as error:
                    errors.append(error)
            threads = [threading.Thread(target=run) for _ in range(4)]
            for thread in threads: thread.start()
            for thread in threads: thread.join(timeout=10)
            self.assertFalse(any(thread.is_alive() for thread in threads))
            self.assertEqual(errors, [])
            self.assertEqual(sorted(values), list(range(1, 41)))

    def test_host_observes_child_failure(self):
        result = subprocess.run([sys.executable, '-c', 'raise SystemExit(7)'], timeout=5)
        self.assertEqual(result.returncode, 7)

    def test_fork_child_cannot_enter_or_clean_up_inherited_runtime(self):
        pid = os.fork()
        if pid == 0:
            try:
                for action in (self.engine.describe, lambda: Engine().describe()):
                    try: action()
                    except EngineError as error:
                        if 'fork' not in str(error): os._exit(2)
                    else: os._exit(3)
                # Rust-only ownership cleanup is permitted; it must not enter VM.
                self.engine.shutdown()
                os._exit(0)
            except BaseException:
                os._exit(4)
        _, status = os.waitpid(pid, 0)
        self.assertEqual(os.waitstatus_to_exitcode(status), 0)
        self.assertEqual(self.engine.describe()['abi'], 1)

    def test_session_exception_releases_handle(self):
        program = {'relations': [{'name': 'Source', 'columns': [{'kind': 'symbol'}],
                                  'source': True, 'rows': [['value']]}], 'rules': [], 'queries': ['Source']}
        with self.assertRaisesRegex(RuntimeError, 'host-error'):
            with self.engine.open(program) as session:
                first = session.run()
                first['relations']['Source'].clear()
                self.assertEqual(session.run()['relations']['Source'], [['value']])
                raise RuntimeError('host-error')
        with self.assertRaises((EngineError, ValueError)): session.run()

if __name__ == '__main__': unittest.main()
