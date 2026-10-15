"""Actual VM cancellation, atomic replacement and checked provenance authority."""
import threading
import unittest
from ascent import Cancellation, Engine, EngineError
from test_module_calls import decode

PLAIN = '''
(define-evidence (make)
  (let (p (ascent (relation input ((x exact-integer?)) '((1)))
          (relation output ((x exact-integer?)))
          ((output X) <-- (input X))))
    (gerbil-ascent-program (.ref p 'relations) (.ref p 'rules) +inf.0 +inf.0 +inf.0 '(input))))
'''
SLOW = '''
(def counter 0)
(def (ticks) counter)
(define-evidence (make)
  (let (p (ascent (relation input ((x exact-integer?)) '((1)))
          (relation output ((x exact-integer?)))
          ((output X) <-- (input X)
           (if (X) (begin (set! counter (+ counter 1))
                          (let loop ((n 200000)) (if (= n 0) #t (loop (- n 1)))))))))
    (gerbil-ascent-program (.ref p 'relations) (.ref p 'rules) +inf.0 +inf.0 +inf.0 '(input))))
'''

class ExecutionAuthority(unittest.TestCase):
    def setUp(self):
        self.engine = Engine()
        self.addCleanup(self.engine.shutdown)

    def test_open_does_not_run_user_rule_callbacks(self):
        with self.engine.dsl(SLOW, trusted=True) as module:
            with module.call('make') as constructor:
                session = constructor.open_session()
            self.addCleanup(session.close)
            with module.call('ticks') as ticks: self.assertEqual(decode(ticks.graph), 0)
            receipt = session.run()
            self.assertEqual(receipt['runIndex'], 1)
            self.assertFalse(receipt['nativeResultReused'])
            with module.call('ticks') as ticks: self.assertGreater(decode(ticks.graph), 0)

    def test_fresh_replace_is_transactional_without_an_initial_solve(self):
        with self.engine.evidence(PLAIN, 'make', trusted=True) as session:
            session.replace({'input': [[7]]})
            receipt = session.run(queries=['output'])
            self.assertEqual(receipt['sourceGeneration'], 1)
            with session.result(receipt) as result: self.assertEqual(decode(result.rows('output')['value']), [[7]])

    def test_cancel_during_replacement_preserves_result_and_generation(self):
        with self.engine.evidence(SLOW, 'make', trusted=True) as session:
            receipt = session.run(queries=['output'])
            with session.result(receipt) as held:
                cancellation = Cancellation()
                timer = threading.Timer(0.1, cancellation.cancel)
                timer.start()
                try:
                    with self.assertRaisesRegex(EngineError, 'canceled'):
                        session.replace({'input': [[n] for n in range(2000)]}, cancellation=cancellation)
                finally: timer.join(timeout=2)
                self.assertEqual(decode(held.rows('output')['value']), [[1]])
                after = session.run(queries=['output'])
                self.assertEqual(after['sourceGeneration'], receipt['sourceGeneration'])
                with session.result(after) as result: self.assertEqual(decode(result.rows('output')['value']), [[1]])

    def test_deadline_during_replacement_preserves_result_and_generation(self):
        with self.engine.evidence(SLOW, 'make', trusted=True) as session:
            receipt = session.run(queries=['output'])
            with session.result(receipt) as held:
                with self.assertRaisesRegex(EngineError, 'deadline'):
                    session.replace({'input': [[n] for n in range(2000)]}, timeout_nanoseconds=1)
                self.assertEqual(decode(held.rows('output')['value']), [[1]])
                self.assertEqual(session.run()['sourceGeneration'], 0)

    def test_zero_deadline_and_precancellation_reject_cached_native_results(self):
        with self.engine.evidence(PLAIN, 'make', trusted=True) as session:
            receipt = session.run()
            with session.result(receipt) as held:
                with self.assertRaisesRegex(EngineError, 'deadline'): session.run(0)
                cancellation = Cancellation(); cancellation.cancel()
                with self.assertRaisesRegex(EngineError, 'canceled'): session.run(cancellation=cancellation)
                self.assertEqual(decode(held.rows('output')['value']), [[1]])

    def test_proof_survives_result_release_and_is_revoked_on_replace(self):
        with self.engine.evidence(PLAIN, 'make', trusted=True) as session:
            receipt = session.run(queries=['output'])
            result = session.result(receipt)
            proof = result.provenance('output')
            self.addCleanup(proof.close)
            identity = proof.graph['sourceIdentity']
            self.assertEqual(proof.graph['sourceGeneration'], 0)
            self.assertTrue(proof.verify())
            result.close()
            self.assertTrue(proof.verify())
            session.replace({'input': [[2]]})
            with self.assertRaises((EngineError, ValueError)): _ = proof.graph
            next_receipt = session.run(queries=['output'])
            with session.result(next_receipt) as current:
                with current.provenance('output') as next_proof:
                    self.assertEqual(next_proof.graph['sourceIdentity'], identity)
                    self.assertEqual(next_proof.graph['sourceGeneration'], 1)
                    self.assertTrue(next_proof.verify())

    def test_proof_revoked_by_native_session_close(self):
        with self.engine.evidence(PLAIN, 'make', trusted=True) as session:
            receipt = session.run(queries=['output'])
            with session.result(receipt) as result: proof = result.provenance('output')
        self.addCleanup(proof.close)
        with self.assertRaises((EngineError, ValueError)): _ = proof.graph
        with self.assertRaises((EngineError, ValueError)): proof.verify()

    def test_limits_apply_to_existing_modules_and_source_admission(self):
        with Engine(max_input_bytes=256) as limited:
            with limited.dsl('(def (echo x) x)', trusted=True) as module:
                with self.assertRaisesRegex(EngineError, 'caller input byte bound'): module.call('echo', 'x' * 1024)
                with module.call('echo', 'ok') as result: self.assertEqual(decode(result.graph), 'ok')
            with self.assertRaisesRegex(EngineError, 'caller input byte bound'):
                limited.open_sources('(ascent-fragment)' + ' ' * 1024)

    def test_canceled_queued_replace_never_commits_after_the_vm_becomes_free(self):
        import tempfile
        import time
        from pathlib import Path
        with tempfile.TemporaryDirectory() as directory:
            marker=Path(directory)/'entered'
            with self.engine.dsl(PLAIN,trusted=True) as module, module.call('make') as value:
                session=value.open_session()
            self.addCleanup(session.close)
            original=session.run()
            result=session.result(original)
            self.addCleanup(result.close)
            with self.engine.dsl('(def (busy marker) (call-with-output-file marker (lambda (port) (display "entered" port))) (thread-sleep! 0.5) #t)',trusted=True) as blocker:
                errors=[]
                def hold():
                    try:
                        with blocker.call('busy',str(marker)): pass
                    except BaseException as error: errors.append(error)
                thread=threading.Thread(target=hold)
                thread.start()
                deadline=time.monotonic()+2
                while not marker.exists() and time.monotonic()<deadline: time.sleep(0.002)
                self.assertTrue(marker.exists(),'blocking call never entered the VM')
                cancellation=Cancellation()
                timer=threading.Timer(0.03,cancellation.cancel)
                timer.start()
                started=time.monotonic()
                try:
                    with self.assertRaisesRegex(EngineError,'cancel'):
                        session.replace({'input':[[9]]},cancellation=cancellation)
                    self.assertLess(time.monotonic()-started,0.25)
                finally:
                    timer.join()
                    thread.join(2)
                self.assertFalse(thread.is_alive())
                self.assertEqual(errors,[])
            self.assertEqual(session.run()['sourceGeneration'],original['sourceGeneration'])
            self.assertEqual(result.rows('output')['value']['format'],'native-value-graph.v1')
            self.assertEqual(session.run()['relations']['output'],[[1]])
