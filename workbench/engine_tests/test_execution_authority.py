"""Rust cancellation, transactional replacement and independently replayed proof leases."""
import threading
import unittest
from unittest.mock import patch
from ascent import Cancellation, Engine, EngineError

PLAIN = '''(define-evidence (make) (sources input) (outputs output)
  (relation input ((x integer?)) ((1))) (relation output ((x integer?)))
  ((output X) <-- (input X)))'''
JOIN = '''(define-evidence (make) (sources input) (outputs output)
  (relation input ((x integer?)) ((1))) (relation output ((x integer?) (y integer?)))
  ((output X Y) <-- (input X) (input Y)))'''

class ExecutionAuthority(unittest.TestCase):
    def setUp(self):
        self.engine = Engine()
        self.addCleanup(self.engine.close)

    def test_open_does_not_run_user_rule_callbacks(self):
        for source in ('(def (callback) (error "entered"))', '(def counter 0) (set! counter 1)'):
            with self.assertRaises(EngineError): self.engine.dsl(source, trusted=True)
        with patch('subprocess.Popen', side_effect=AssertionError('external execution')):
            with self.engine.evidence(PLAIN, trusted=True) as session:
                self.assertEqual(session.run()['relations']['output'], [[1]])
                self.assertFalse(self.engine.describe()['schemeVm'])

    def test_fresh_replace_is_transactional_without_an_initial_solve(self):
        with self.engine.evidence(PLAIN, trusted=True) as session:
            session.replace({'input': [[7]]})
            receipt = session.run()
            self.assertEqual(receipt['sourceGeneration'], 1)
            self.assertEqual(receipt['relations']['output'], [[7]])

    def test_cancel_during_replacement_preserves_result_and_generation(self):
        with self.engine.evidence(JOIN, trusted=True) as session:
            receipt = session.run()
            with session.result(receipt) as held:
                cancellation = Cancellation()
                timer = threading.Timer(0.0005, cancellation.cancel)
                timer.start()
                try:
                    with self.assertRaisesRegex(EngineError, 'canceled'):
                        session.replace({'input': [[n] for n in range(2000)]}, cancellation=cancellation)
                finally: timer.join(timeout=2)
                self.assertEqual(held.rows('output')['rows'], [[1, 1]])
                after = session.run()
                self.assertEqual(after['sourceGeneration'], receipt['sourceGeneration'])
                self.assertEqual(after['relations']['output'], [[1, 1]])

    def test_deadline_during_replacement_preserves_result_and_generation(self):
        with self.engine.evidence(JOIN, trusted=True) as session:
            receipt = session.run()
            with session.result(receipt) as held:
                with self.assertRaisesRegex(EngineError, 'deadline'):
                    session.replace({'input': [[n] for n in range(2000)]}, timeout_nanoseconds=1)
                self.assertEqual(held.rows('output')['rows'], [[1, 1]])
                self.assertEqual(session.run()['sourceGeneration'], 0)

    def test_zero_deadline_and_precancellation_reject_cached_native_results(self):
        with self.engine.evidence(PLAIN, trusted=True) as session:
            receipt = session.run()
            with session.result(receipt) as held:
                with self.assertRaisesRegex(EngineError, 'deadline'): session.run(0)
                cancellation = Cancellation()
                cancellation.cancel()
                self.assertTrue(cancellation.canceled)
                with self.assertRaisesRegex(EngineError, 'canceled'): session.run(cancellation=cancellation)
                self.assertEqual(held.rows('output')['rows'], [[1]])

    def test_proof_survives_result_release_and_is_revoked_on_replace(self):
        with self.engine.evidence(PLAIN, trusted=True) as session:
            result = session.result(session.run())
            proof = result.explanation('output')
            self.addCleanup(proof.close)
            identity = proof.graph['scope']['sourceIdentity']
            self.assertEqual(proof.source_generation, 0)
            self.assertTrue(proof.verify())
            result.close()
            self.assertTrue(proof.verify())
            session.replace({'input': [[2]]})
            self.assertFalse(proof.current)
            self.assertEqual(proof.graph['scope']['sourceIdentity'], identity)
            with self.assertRaises(EngineError): proof.verify()
            with session.result(session.run()) as current:
                with current.explanation('output') as next_proof:
                    self.assertEqual(next_proof.graph['scope']['sourceIdentity'], identity)
                    self.assertEqual(next_proof.source_generation, 1)
                    self.assertTrue(next_proof.verify())

    def test_proof_revoked_by_native_session_close(self):
        with self.engine.evidence(PLAIN, trusted=True) as session:
            with session.result(session.run()) as result: proof = result.explanation('output')
        self.addCleanup(proof.close)
        self.assertFalse(proof.current)
        with self.assertRaises(EngineError): _ = proof.graph
        with self.assertRaises(EngineError): proof.verify()

    def test_limits_apply_to_existing_modules_and_source_admission(self):
        with Engine(max_request_bytes=2048) as limited:
            with limited.dsl(PLAIN, trusted=True) as session:
                with self.assertRaisesRegex(EngineError, 'request byte bound'):
                    session.replace({'input': [[n] for n in range(1000)]})
                session.replace({'input': [[7]]}).value()
                self.assertEqual(session.run(result_format='typed-rows').value()['relations']['output'], [[7]])
            with self.assertRaisesRegex(EngineError, 'request byte bound'):
                limited.open_sources('(ascent-fragment)' + ' ' * 2048)

    def test_canceled_queued_replace_never_commits_after_the_vm_becomes_free(self):
        # Rust has no VM callback queue. Exercise concurrent owner requests and
        # pre-cancellation without claiming an observed native-lock acquisition.
        with self.engine.evidence(PLAIN, trusted=True) as session:
            original = session.run()
            cancellation = Cancellation()
            cancellation.cancel()
            errors = []
            def repeat():
                try:
                    for _ in range(30):
                        receipt = session.run()
                        self.assertEqual(receipt['relations']['output'], [[1]])
                        session.result(receipt).close()
                except BaseException as error: errors.append(error)
            thread = threading.Thread(target=repeat)
            thread.start()
            try:
                with self.assertRaisesRegex(EngineError, 'canceled'):
                    session.replace({'input': [[9]]}, cancellation=cancellation)
            finally: thread.join(timeout=2)
            self.assertFalse(thread.is_alive())
            self.assertEqual(errors, [])
            self.assertEqual(session.run()['sourceGeneration'], original['sourceGeneration'])
            self.assertEqual(session.run()['relations']['output'], [[1]])

if __name__ == '__main__': unittest.main()
