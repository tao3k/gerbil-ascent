"""Fresh-process scope lifetime bounds, without any downstream Scheme imports."""
import unittest
from ascent_engine import Engine, EngineError
from test_native_module_calls import decode


class EvidenceDSLLifecycle(unittest.TestCase):
    def test_complete_runtime_scope_limit_is_not_reset_by_close(self):
        with Engine() as engine:
            with self.assertRaises(EngineError):
                engine.dsl('(import :gerbil/core)', trusted=True)
            with self.assertRaises(EngineError):
                engine.dsl('(unknown-dsl-form)', trusted=True)
            with engine.dsl('(def (answer) 42)', trusted=True) as retained:
                for _ in range(62):
                    with engine.dsl('(def (answer) 1)', trusted=True) as owner:
                        with owner.call('answer') as value:
                            self.assertEqual(decode(value.graph), 1)
                with self.assertRaisesRegex(EngineError, 'runtime load limit'):
                    engine.dsl('(def (answer) 2)', trusted=True)
                with retained.call('answer') as value:
                    self.assertEqual(decode(value.graph), 42)
            with self.assertRaisesRegex(EngineError, 'runtime load limit'):
                engine.dsl('(def (answer) 2)', trusted=True)
            self.assertEqual(engine.request({'operation': 'describe'})['abi'], 1)


if __name__ == '__main__': unittest.main()
