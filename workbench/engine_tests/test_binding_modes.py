# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Actual Core ABI error cleanup, Rust owner serialization and fork isolation."""
import os
import signal
import subprocess
import sys
import threading
import unittest
from ascent import Engine, EngineError

SOURCE = '''(define-program (make) (sources input) (outputs output)
  (relation input ((x integer?)) ((1))) (relation output ((x integer?)))
  ((output X) <-- (input X)))'''

class BindingContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        before = signal.getsignal(signal.SIGCHLD)
        cls.engine = Engine()
        cls.engine.describe()
        if signal.getsignal(signal.SIGCHLD) != before:
            raise AssertionError('engine changed host child-reaping policy')

    @classmethod
    def tearDownClass(cls):
        cls.engine.close()
        with cls().assertRaises(EngineError): cls.engine.describe()

    def test_work_distribution_reaches_the_installed_twelve_thread_owner(self):
        for distribution in ('adaptive', 'across-requests', 'within-request'):
            with self.subTest(distribution=distribution):
                with Engine(workers=12, work_distribution=distribution) as engine:
                    self.assertEqual(engine.work_distribution, distribution)
                    self.assertEqual(engine.describe()['workers'], 12)
                    with engine.rules(SOURCE, trusted=True) as session:
                        first = session.run()
                        self.assertEqual(first['relations']['output'], [[1]])
                        session.result(first).close()
                        session.replace({'input': [[2]]})
                        changed = session.run()
                        self.assertEqual(changed['relations']['output'], [[2]])
                        session.result(changed).close()
        with self.assertRaises(ValueError):
            Engine(workers=12, work_distribution='unknown')

    def test_result_memory_is_released_on_c_errors(self):
        with self.engine.dsl(SOURCE, trusted=True) as owner:
            for payload in ({}, {'operation': 'unknown'}, {'method': 'rows', 'handle': -1, 'query': 'output'}):
                with self.assertRaises(EngineError):
                    with owner.call(payload) as value: value.value()
                with owner.run(result_format='typed-rows') as value:
                    self.assertEqual(value.value()['relations']['output'], [[1]])

    def test_typed_error_does_not_poison_next_request(self):
        with self.assertRaises(EngineError): self.engine.dsl('(def (broken)', trusted=True)
        self.assertEqual(self.engine.describe()['abi'], 1)

    def test_backend_switch_rejects_before_loading_another_runtime(self):
        other = Engine()
        other.close()
        with self.assertRaises(EngineError): other.describe()
        self.assertEqual(self.engine.describe()['abi'], 1)
        for backend in ('auto', 'scheme', 'unknown'):
            with self.assertRaises(ValueError): Engine(backend=backend)
        with self.assertRaises(TypeError): Engine('not-a-library')

    def test_wrong_os_thread_is_rejected(self):
        # The ordinary Rust session serializes state; the fixed C owner is
        # separately thread-affine and is not a VM or a cross-thread callback.
        with self.engine.rules(SOURCE, trusted=True) as session:
            values, errors = [], []
            def run():
                try:
                    for _ in range(10):
                        receipt = session.run()
                        values.append(receipt['runIndex'])
                        session.result(receipt).close()
                except BaseException as error: errors.append(error)
            threads = [threading.Thread(target=run) for _ in range(4)]
            for thread in threads: thread.start()
            for thread in threads: thread.join(timeout=10)
            self.assertFalse(any(thread.is_alive() for thread in threads))
            self.assertEqual(errors, [])
            self.assertEqual(len(values), 40)
            self.assertEqual(len(set(values)), 40)
            self.assertEqual(max(values) - min(values), 39)

    def test_host_observes_child_failure(self):
        result = subprocess.run([sys.executable, '-c', 'raise SystemExit(7)'], timeout=5)
        self.assertEqual(result.returncode, 7)

    def test_fork_child_cannot_enter_or_clean_up_inherited_runtime(self):
        pid = os.fork()
        if pid == 0:
            try:
                try: self.engine.describe()
                except EngineError: pass
                else: os._exit(3)
                self.engine.close()
                try: Engine()
                except EngineError: pass
                else: os._exit(5)
                # A fork inherits Rayon synchronization state, not its workers.
                # Exec establishes a genuinely independent runtime instance.
                script = f'''from ascent import Engine
with Engine() as independent:
    assert independent.describe()['schemeVm'] is False
    with independent.rules({SOURCE!r}, trusted=True) as session:
        assert session.run()['relations']['output'] == [[1]]
'''
                os.execv(sys.executable, [sys.executable, '-c', script])
            except BaseException: os._exit(4)
        _, status = os.waitpid(pid, 0)
        self.assertEqual(os.waitstatus_to_exitcode(status), 0)
        self.assertEqual(self.engine.describe()['abi'], 1)

    def test_session_exception_releases_handle(self):
        program = {'relations': [{'name': 'Source', 'columns': [{'kind': 'symbol'}],
                                  'source': True, 'rows': [['value']]}],
                   'rules': [], 'queries': ['Source']}
        with self.assertRaisesRegex(RuntimeError, 'host-error'):
            with self.engine.open(program) as session:
                first = session.run()
                first['relations']['Source'].clear()
                self.assertEqual(session.run()['relations']['Source'], [['value']])
                raise RuntimeError('host-error')
        with self.assertRaises(EngineError): session.run()

if __name__ == '__main__': unittest.main()
