"""Installed Rust/PyO3 ownership and legacy typed argument encodings."""
import unittest
import ascent


class ModuleValues(unittest.TestCase):
    def setUp(self):
        self.engine = ascent.Engine()

    def tearDown(self):
        self.engine.shutdown()

    def test_legacy_tagged_complex_values_round_trip(self):
        with self.engine.dsl('(def (echo x) x)', trusted=True) as module:
            cases = [
                ({'type': 'number', 'value': '2/6'}, 'number'),
                ({'type': 'character', 'value': 97}, 'character'),
                ({'type': 'vector', 'value': [1, {'type': 'symbol', 'value': 's'}]}, 'vector'),
                ({'type': 'u8vector', 'value': [0, 255]}, 'u8vector'),
                ({'type': 'pair', 'car': 1, 'cdr': 2}, 'pair'),
            ]
            for argument, kind in cases:
                with module.call('echo', argument) as value:
                    graph = value.graph
                    root = graph['root']
                    if 'ref' in root:
                        root = next(node for node in graph['nodes'] if node['id'] == root['ref'])
                    self.assertEqual(root['type'], kind)
                    if kind == 'number': self.assertEqual(root['value'], '1/3')
                    if kind == 'character': self.assertEqual(root['value'], 97)
                    if kind == 'u8vector': self.assertEqual(root['items'], [0, 255])

    def test_child_references_retain_identity_and_reject_unreachable_nodes(self):
        source = '(def (make) (let (v (vector 17)) (vector v v))) (def (echo x) x)'
        with self.engine.dsl(source, trusted=True) as module:
            with module.call('make') as outer:
                graph = outer.graph
                root = next(n for n in graph['nodes'] if n['id'] == graph['root']['ref'])
                child = root['items'][0]['ref']
                self.assertEqual(root['items'][0], root['items'][1])
                with module.call('echo', outer.reference(child)) as retained:
                    self.assertEqual(retained.graph['root'], {'ref': child})
                with self.assertRaises(ascent.EngineError): outer.reference(10**9)
                reference = outer.reference(child)
            with self.assertRaises(ascent.EngineError): module.call('echo', reference)

    def test_components_only_load_the_dependency_closure(self):
        manifest = {'schema': 'ascent.rule-components.v1', 'components': [
            {'id': 'base', 'source': 'base.ss', 'exports': ['answer'], 'dependencies': []},
            {'id': 'entry', 'source': 'entry.ss', 'exports': ['build'],
             'dependencies': [{'component': 'base', 'bindings': ['answer']}]},
            {'id': 'unused', 'source': 'unused.ss', 'exports': ['fail'], 'dependencies': []},
        ]}
        sources = {'base.ss': '(def (answer) 4)', 'entry.ss': '(def (build) (answer))',
                   'unused.ss': '(unknown-dsl-form)'}
        with self.engine.components(manifest, sources, 'entry', trusted=True) as module:
            self.assertEqual(module.components, ('base', 'entry'))
            with module.call('build') as value: self.assertEqual(value.graph['root']['value'], '4')
            with self.assertRaises(ascent.EngineError): module.call('answer')
            with module.call('answer', component='base') as value: self.assertEqual(value.graph['root']['value'], '4')
            with self.assertRaises(ascent.EngineError): module.call('fail', component='unused')
        manifest['components'][2]['dependencies'] = [{'component': 'unused', 'bindings': ['fail']}]
        with self.assertRaises(ascent.EngineError):
            self.engine.components(manifest, sources, 'entry', trusted=True)

    def test_authorization_and_shutdown_invalidate_calls_and_observations(self):
        with self.assertRaisesRegex(ValueError, 'explicitly authorized'):
            self.engine.dsl('(def (answer) 1)')
        module = self.engine.dsl('(def (answer) 1)', trusted=True)
        value = module.call('answer')
        self.engine.shutdown()
        with self.assertRaises(ValueError): module.call('answer')
        with self.assertRaises(ValueError): value.graph
        value.close(); module.close(); module.close()

    def test_owned_values_are_direct_call_arguments_without_graph_projection(self):
        source = '(def (make n) (lambda (x) (+ n x))) (def (invoke f x) (f x)) (def (echo x) x)'
        with self.engine.dsl(source, trusted=True) as module:
            with module.call('make', 7) as function:
                with module.call('invoke', function, 5) as value:
                    self.assertEqual(value.graph['root']['value'], '12')
                with self.engine.dsl(source, trusted=True) as foreign:
                    with self.assertRaises(ascent.EngineError): foreign.call('echo', function)
            with self.assertRaises(ascent.EngineError): module.call('echo', function)

    def test_tagged_byte_and_character_values_reject_boolean_integer_coercion(self):
        with self.engine.dsl('(def (echo x) x)', trusted=True) as module:
            for argument in [
                {'type': 'u8vector', 'value': [True]},
                {'type': 'u8vector', 'value': [256]},
                {'type': 'u8vector', 'value': b'abc'},
                {'type': 'character', 'value': True},
                {'type': 'character', 'value': 0xd800},
            ]:
                with self.assertRaises(ascent.EngineError): module.call('echo', argument)
            with module.call('echo', {'type': 'u8vector', 'value': [0, 255]}) as value:
                self.assertEqual(value.graph['nodes'][0]['items'], [0, 255])

    def test_python_callers_share_mutable_closure_locations_safely(self):
        from concurrent.futures import ThreadPoolExecutor
        source = '(def (counter n) (lambda () (set! n (+ n 1)) n))'
        with self.engine.dsl(source, trusted=True) as module, module.call('counter', 0) as counter:
            def invoke(_):
                with counter.apply() as value:
                    return int(value.graph['root']['value'])
            with ThreadPoolExecutor(max_workers=8) as pool:
                results = list(pool.map(invoke, range(40)))
            self.assertEqual(sorted(results), list(range(1, 41)))

    def test_python_integer_input_uses_native_conversion_without_virtual_string_calls(self):
        class Integer(int):
            def __str__(self):
                raise AssertionError('native integer conversion must not call Python __str__')
        with self.engine.dsl('(def (echo x) x)', trusted=True) as module:
            with module.call('echo', Integer(2**256)) as value:
                self.assertEqual(value.graph['root']['value'], str(2**256))
