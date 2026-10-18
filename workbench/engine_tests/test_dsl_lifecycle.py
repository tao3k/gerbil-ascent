"""Caller-owned declaration admission limits; no process-wide VM/expander quota."""
import unittest
from ascent import Engine, EngineError

SOURCE = '''(define-evidence (make) (sources) (outputs answer)
  (relation answer ((value integer?)) ((42))))'''

class EvidenceDSLLifecycle(unittest.TestCase):
    def test_complete_runtime_scope_limit_is_not_reset_by_close(self):
        with Engine(max_source_scopes=64) as engine:
            for source in ('(import :gerbil/core)', '(unknown-dsl-form)'):
                with self.assertRaises(EngineError): engine.dsl(source, trusted=True)
            with engine.dsl(SOURCE, trusted=True) as retained:
                for _ in range(61):
                    with engine.dsl(SOURCE.replace('42', '1'), trusted=True) as owner:
                        self.assertEqual(owner.run(result_format='typed-rows').value()['relations']['answer'], [[1]])
                self.assertEqual(engine.describe()['sourceScopes'], 64)
                with self.assertRaisesRegex(EngineError, 'source scope limit'):
                    engine.dsl(SOURCE, trusted=True)
                self.assertEqual(retained.run(result_format='typed-rows').value()['relations']['answer'], [[42]])
            with self.assertRaisesRegex(EngineError, 'source scope limit'):
                engine.evidence(SOURCE, trusted=True)
            with Engine() as unlimited:
                self.assertIsNone(unlimited.max_source_scopes)
                for _ in range(80):
                    with unlimited.dsl(SOURCE, trusted=True) as owner:
                        self.assertTrue(owner.run().value()['complete'])
                self.assertEqual(unlimited.describe()['sourceScopes'], 80)
                self.assertEqual(engine.describe()['sourceScopes'], 64)
            manifest = {'schema': 'ascent.evidence-components.v1', 'components': [
                {'id': 'entry', 'source': 'entry.ss', 'exports': ['make'], 'dependencies': []}]}
            with Engine(max_source_scopes=1) as limited:
                with limited.components(manifest, {'entry.ss': SOURCE}, 'entry', trusted=True) as factory:
                    with factory.call('make') as declaration:
                        with self.assertRaisesRegex(EngineError, 'source scope limit'):
                            declaration.open_session()
                with self.assertRaisesRegex(EngineError, 'source scope limit'):
                    limited.components(manifest, {'entry.ss': SOURCE}, 'entry', trusted=True)
                self.assertEqual(limited.describe()['sourceScopes'], 1)
            for invalid in (0, -1, True, False, '64'):
                with self.assertRaises((ValueError, TypeError, OverflowError)):
                    Engine(max_source_scopes=invalid)

if __name__ == '__main__': unittest.main()
