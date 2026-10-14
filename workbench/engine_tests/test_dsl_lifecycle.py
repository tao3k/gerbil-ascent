"""Fresh-process scope lifetime bounds, without any downstream Scheme imports."""
import unittest
from ascent_engine import Engine, EngineError
from test_module_calls import decode


class EvidenceDSLLifecycle(unittest.TestCase):
    def test_complete_runtime_scope_limit_is_not_reset_by_close(self):
        with Engine(max_source_scopes=64) as engine:
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
            unlimited = Engine()
            self.assertIsNone(unlimited.max_source_scopes)
            self.assertEqual(unlimited.request({'operation': 'describe'})['sourceScopes'], 64)
            for _ in range(16):
                with unlimited.dsl('(def (answer) 3)', trusted=True) as owner:
                    with owner.call('answer') as value:
                        self.assertEqual(decode(value.graph), 3)
            self.assertEqual(engine.request({'operation': 'describe'})['sourceScopes'], 80)
            with self.assertRaisesRegex(EngineError, 'runtime load limit'):
                engine.dsl('(def (answer) 2)', trusted=True)
            manifest = {'schema': 'ascent.evidence-components.v1', 'components': [
                {'id': 'base', 'source': 'base.ss', 'exports': ['answer'], 'dependencies': []},
                {'id': 'entry', 'source': 'entry.ss', 'exports': ['build'],
                 'dependencies': [{'component': 'base', 'bindings': ['answer']}]}]}
            sources = {'base.ss': '(def (answer) 4)', 'entry.ss': '(def (build) (answer))'}
            preflight = Engine(max_source_scopes=81)
            for invoke in (
                    lambda: preflight.components(manifest, sources, 'entry', trusted=True),
                    lambda: preflight.evidence_components(manifest, sources, 'entry', 'build', trusted=True),
                    lambda: engine.evidence('(def (build) 1)', 'build', trusted=True)):
                with self.assertRaisesRegex(EngineError, 'runtime load limit'):
                    invoke()
            self.assertEqual(engine.request({'operation': 'describe'})['sourceScopes'], 80)
            with unlimited.components(manifest, sources, 'entry', trusted=True) as owner:
                with owner.call('build') as value:
                    self.assertEqual(decode(value.graph), 4)
            self.assertEqual(engine.request({'operation': 'describe'})['sourceScopes'], 82)
            for invalid in (False, 0, -1, '64'):
                with self.assertRaisesRegex(EngineError, 'positive integer'):
                    unlimited.request({'operation': 'dsl-open', 'source': '(def (answer) 1)',
                                       'trusted': True, 'maxSourceScopes': invalid})
            for invalid in (0, -1, True, '64'):
                with self.assertRaises(ValueError):
                    Engine(max_source_scopes=invalid)


if __name__ == '__main__': unittest.main()
