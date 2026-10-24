"""Independent complete lookup refinement through the actual API and ABI."""
import unittest
import test_uf_materialization as oracle

class UFLookupTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        oracle.UFMaterializationTests.setUpClass.__func__(cls)

    @classmethod
    def tearDownClass(cls):
        oracle.UFMaterializationTests.tearDownClass.__func__(cls)

    def test_grouped_selectors_follow_independent_closure_and_held_order(self):
        edges = [[g, i, (i + 1) % 32] for g in (0, 7) for i in range(32)]
        with self.engine.reachability() as state:
            for edge in edges:
                state.insert(edge, budget=10000)
                pass
            with state.freeze() as frozen:
                held = frozen
                public = held.rows()
                full = public
                truth = {(g, a, b) for g in (0, 7) for a, b in oracle.closure([edge[1:] for edge in edges if edge[0] == g])}
                self.assertEqual(set(map(tuple, full)), truth)
                self.assertEqual(len(full), len(truth))
                for edge in ([0, 31, 32], [0, 32, 0], [7, 31, 32]):
                    state.insert(edge, budget=10000)
                    pass
                for columns, key in (([], []), ([1], [0]), ([2], [0]), ([2, 0], [0, 7]), ([1, 1], [0, 1]), ([0], [99])):
                    wanted = [row for row in full if all((row[c] == k for c, k in zip(columns, key)))]
                    with self.subTest(columns=columns, key=key):
                        for _ in range(2):
                            public = held.rows(columns, key)
                            self.assertEqual(public, wanted)

    def test_weighted_products_keep_checked_selectors_after_component_retirement(self):
        base = [[i, i + 1] for i in range(48)] + [[16, 0], [40, 24]]
        edges = [[group, *edge] for group in (0, 7) for edge in base]
        truth = {(group, a, b) for group in (0, 7) for a, b in oracle.closure(base)}
        with self.engine.reachability() as state:
            for edge in edges:
                state.insert(edge, budget=10000)
                pass
            with state.freeze() as frozen:
                held = frozen
                public = held.rows()
                full = public
                self.assertEqual(len(full), len(truth))
                self.assertEqual(set(map(tuple, full)), truth)
                state.insert([0, 48, 0], budget=10000)
                pass
                for columns, key in (([1], [0]), ([2], [24]), ([1, 2], [0, 24]), ([2, 0], [24, 7]), ([1, 1], [0, 1]), ([], [])):
                    wanted = [row for row in full if all((row[c] == k for c, k in zip(columns, key)))]
                    for _ in range(2):
                        with self.subTest(columns=columns, key=key):
                            public = held.rows(columns, key)
                            self.assertEqual(public, wanted)

    def test_union_and_explicit_fallback_preserve_complete_order(self):
        # Direct Graph union replaces the old runtime-procedure fallback.
        with self.engine.source_graph('left', 2, [[0, 0], [0, 1]]) as left:
            with self.engine.source_graph('right', 2, [[1, 0]]) as right:
                with left.union(right) as graph, graph.open_session('union') as session:
                    full = session.run()['relations']['union']
                    self.assertEqual(full, [[0, 0], [0, 1], [1, 0]])
                    for columns, key, wanted in (([], [], full), ([1], [0], [[0, 0], [1, 0]]),
                                                 ([0, 0], [0, 1], [])):
                        guards = ' '.join(f'(guard (C{c}) (lambda (v) (= v {k})))' for c, k in zip(columns, key))
                        source = f'''(define-program (make) (sources input) (outputs selected)
                          (relation input ((x integer?) (y integer?)))
                          (relation selected ((x integer?) (y integer?)))
                          ((selected C0 C1) <-- (input C0 C1) {guards}))'''
                        with self.engine.rules(source, trusted=True) as selected:
                            selected.replace({'input': full})
                            self.assertEqual(selected.run()['relations']['selected'], wanted)

    def test_explicit_empty_query_keeps_visitor_order(self):
        # Arbitrary runtime visitors are excluded by the declared no-VM contract.
        # Explicit Graph results are canonical; cuts retain their traversal order.
        with self.engine.source_graph('input', 2, [[1, 1], [0, 0]]) as graph:
            with graph.open_session('rows') as session:
                self.assertEqual(session.run()['relations']['rows'], [[0, 0], [1, 1]])
                self.assertEqual(session.run()['relations']['rows'], [[0, 0], [1, 1]])
        with self.engine.reachability() as state:
            state.insert([1, 1], budget=1)
            state.insert([0, 0], budget=1)
            with state.freeze() as cut:
                full = cut.rows()
                self.assertEqual(set(map(tuple, full)), {(0, 0), (1, 1)})
                self.assertEqual(cut.rows([], []), full)
