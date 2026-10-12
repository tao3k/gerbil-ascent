# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Public upstream objects through the real ABI, not a Python DSL substitute."""
from contextlib import ExitStack
import unittest
from ascent_engine import Engine, EngineError

INTERFACE = ':gerbil-ascent/program/interface'
QUALIFICATION = ':gerbil-ascent/t/qualification/evidence-api-module'


def symbol(name):
    return {'type': 'symbol', 'value': name}


def decode(graph):
    """Test-only decoding of an acyclic native observation."""
    nodes = {node['id']: node for node in graph['nodes']}
    def item(value):
        if 'ref' in value:
            value = nodes[value['ref']]
        kind = value['type']
        if kind == 'null': return []
        if kind == 'number': return int(value['value'])
        if kind in ('string', 'symbol', 'boolean'): return value['value']
        if kind == 'vector': return [item(v) for v in value['items']]
        if kind == 'pair': return [item(value['car']), *item(value['cdr'])]
        raise AssertionError(kind)
    return item(graph['root'])


class NativeModuleCallTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.engine = Engine()

    @classmethod
    def tearDownClass(cls): cls.engine.shutdown()

    def test_upstream_operator_composition_retained_session_and_withdrawal(self):
        with self.engine.module(INTERFACE) as module, ExitStack() as stack:
            def call(name, *args, **kw): return stack.enter_context(module.call(name, *args, **kw))
            source = call('relational-op-source', symbol('edge'), 2, [[0, 1], [1, 2]])
            operator = call('relational-op-project', source.reference(), [1])
            fragment = call('relational-op-fragment', operator.reference(), symbol('targets'))
            program = call('relational-compose', [fragment.reference()], 16, 64, 128)
            session = call('relational-open-session', program.reference())
            solution = call('relational-session-run', session.reference())
            rows = call('relational-query', solution.reference(), fragment.reference(), symbol('targets'))
            self.assertEqual(sorted(decode(rows.graph)), [[1], [2]])
            call('relational-session-replace-source!', session.reference(), fragment.reference(),
                 symbol('edge'), [[7, 8]])
            updated = call('relational-session-run', session.reference())
            rows = call('relational-query', updated.reference(), fragment.reference(), symbol('targets'))
            self.assertEqual(decode(rows.graph), [[8]])
            with self.assertRaises(EngineError):
                module.call('relational-session-replace-source!', session.reference(), fragment.reference(),
                            symbol('edge'), [[1]])
            rows = call('relational-query', updated.reference(), fragment.reference(), symbol('targets'))
            self.assertEqual(decode(rows.graph), [[8]])

    def test_cross_module_lattice_program_without_wire_projection(self):
        with self.engine.module(QUALIFICATION) as module, ExitStack() as stack:
            def call(name, *args, **kw): return stack.enter_context(module.call(name, *args, **kw))
            evidence = call('make-lattice', [[0, 9], [0, 2], [1, 7]])
            program = call('evidence-module-program', evidence.reference(),
                           module=':gerbil-ascent/interface/evidence-module')
            with self.assertRaisesRegex(EngineError, 'untrusted relational lattice'):
                module.call('relational-open-program-session', program.reference(), module=INTERFACE)
            session = call('gerbil-ascent-open-session', program.reference(), module=INTERFACE)
            solution = call('gerbil-ascent-session-run', session.reference(), module=INTERFACE)
            reader = call('.ref', solution.reference(), symbol('rows-of'), module=':clan/poo/object')
            rows = stack.enter_context(reader.apply(symbol('best')))
            self.assertEqual(sorted(decode(rows.graph)), [[0, 2], [1, 7]])

    def test_multiple_native_return_values_and_prepared_query(self):
        with self.engine.module(INTERFACE) as module, ExitStack() as stack:
            def call(name, *args): return stack.enter_context(module.call(name, *args))
            source = call('relational-op-source', symbol('edge'), 2, [[0, 1]])
            operator = call('relational-op-project', source.reference(), [1])
            fragment = call('relational-op-fragment', operator.reference(), symbol('target'))
            program = call('relational-compose', [fragment.reference()], 16, 64, 128)
            admission = call('relational-admit', program.reference())
            solution = call('relational-solve', admission.reference())
            query = call('relational-prepare-query', fragment.reference(), symbol('target'))
            self.assertIn('opaque', str(query.graph))
            # No Python procedure invocation, expansion or inference is used.
            rows = call('relational-query', solution.reference(), fragment.reference(), symbol('target'))
            self.assertEqual(decode(rows.graph), [[1]])
            with query.apply(solution.reference()) as invoked:
                self.assertEqual(decode(invoked.graph), [[1]])
            with module.call('native-values', 3, 5, module=QUALIFICATION) as multiple:
                self.assertEqual(multiple.receipt['valueCount'], 2)
                self.assertEqual(decode(multiple.graph), [3, 5])

    def test_native_prepared_change_and_retained_operator_updates(self):
        with self.engine.module(INTERFACE) as module, ExitStack() as stack:
            def call(name, *args, **kw): return stack.enter_context(module.call(name, *args, **kw))
            transformer = call('make-projection-transformer', module=QUALIFICATION)
            plan = call('relational-op-prepare-change', transformer.reference())
            change = call('relational-op-change', plan.reference(), [[0, 1]], [[2, 3]], 16)
            self.assertEqual(change.receipt['valueCount'], 3)
            self.assertEqual(decode(change.graph), [[[1]], [[1], [3]], [[3]]])
            retained = call('relational-op-open-retained', transformer.reference(), [[0, 1]], 16, 64, 128)
            call('relational-op-retained-replace!', retained.reference(), [[7, 8]])
            rows = call('relational-op-retained-rows', retained.reference())
            self.assertEqual(decode(rows.graph), [[8]])

    def test_unknown_export_failed_call_released_and_foreign_references(self):
        with self.engine.module(INTERFACE) as module:
            with self.assertRaises(EngineError): module.call('identity', 1)
            with self.assertRaises(EngineError): module.call('relational-op-source', symbol('bad'), 2, [[1]])
            value = module.call('relational-op-source', symbol('ok'), 1, [[1]])
            ref = value.reference()
            with self.engine.module(INTERFACE) as other, self.assertRaises(EngineError):
                other.call('relational-op-project', ref, [0])
            value.close()
            with self.assertRaises(EngineError): module.call('relational-op-project', ref, [0])
            with self.assertRaises(ValueError): value.reference()
        with self.assertRaises(ValueError): module.call('relational-op-source', symbol('x'), 1, [])

    def test_owner_capacity_releases_and_does_not_select_python_fallback(self):
        with self.engine.module(INTERFACE) as module:
            values = [module.call('relational-op-source', symbol('x'), 1, []) for _ in range(64)]
            try:
                with self.assertRaises(EngineError): module.call('relational-op-source', symbol('x'), 1, [])
                values.pop().close()
                with module.call('relational-op-source', symbol('x'), 1, []) as value:
                    self.assertTrue(value.reference())
            finally:
                for value in values: value.close()

    def test_independent_explanation_lifetime_and_repeated_cleanup(self):
        with self.engine.open_module(QUALIFICATION, 'make-values', [1]) as session:
            with session.result(session.run(queries=['output'])) as result:
                # More than the native 64-result cap succeeds by releasing each proof.
                for _ in range(70):
                    with result.explanation('output') as proof:
                        self.assertIn('dependencies', str(proof.graph))
                        self.assertIn('gap', str(proof.graph))
                    with self.assertRaises(ValueError): proof.graph
                self.assertEqual(result.rows('output')['sourceGeneration'], 0)


if __name__ == '__main__': unittest.main()
