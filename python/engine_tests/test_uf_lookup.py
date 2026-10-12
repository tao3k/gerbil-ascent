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
        with self.engine.module(oracle.UF) as owner:
            with owner.call('gerbil-ascent-trrel-uf-state') as state:
                for edge in edges:
                    with owner.call('gerbil-ascent-trrel-uf-count-insert!', state.reference(), edge, 10000):
                        pass
                with owner.call('gerbil-ascent-trrel-uf-freeze', state.reference(), True) as frozen:
                    held = frozen.reference()
                    with owner.call('gerbil-ascent-view-rows', held, module=oracle.VIEW) as public:
                        full = oracle.rows(public.graph)
                    truth = {(g, a, b) for g in (0, 7)
                             for a, b in oracle.closure([edge[1:] for edge in edges if edge[0] == g])}
                    self.assertEqual(set(map(tuple, full)), truth)
                    self.assertEqual(len(full), len(truth))
                    for edge in ([0, 31, 32], [0, 32, 0], [7, 31, 32]):
                        with owner.call('gerbil-ascent-trrel-uf-count-insert!', state.reference(), edge, 10000):
                            pass
                    for columns, key in (([], []), ([1], [0]), ([2], [0]), ([2, 0], [0, 7]),
                                         ([1, 1], [0, 1]), ([0], [99])):
                        wanted = [row for row in full if all(row[c] == k for c, k in zip(columns, key))]
                        with self.subTest(columns=columns, key=key):
                            for function, module in (('gerbil-ascent-trrel-uf-view-lookup', oracle.UF),
                                                     ('gerbil-ascent-view-rows', oracle.VIEW)):
                                with owner.call(function, held, columns, key, module=module) as public:
                                    self.assertEqual(oracle.rows(public.graph), wanted)

    def test_union_and_explicit_fallback_preserve_complete_order(self):
        with self.engine.module(oracle.VIEW) as owner:
            with owner.call('gerbil-ascent-explicit-view', [[0, 0], [0, 1]], 2) as left:
                with owner.call('gerbil-ascent-explicit-view', [[1, 0]], 1) as right:
                    with owner.call('gerbil-ascent-view-union', left.reference(), right.reference()) as union:
                        for columns, key, wanted in (([], [], [[0, 0], [0, 1], [1, 0]]),
                                                     ([1], [0], [[0, 0], [1, 0]]),
                                                     ([0, 0], [0, 1], [])):
                            with owner.call('gerbil-ascent-view-rows', union.reference(), columns, key) as public:
                                self.assertEqual(oracle.rows(public.graph), wanted)

    def test_explicit_empty_query_keeps_visitor_order(self):
        with self.engine.module(':gerbil-ascent/t/qualification/evidence-api-module') as owner:
            with owner.call('make-export-view', [[0, 0], [1, 1]], [[1, 1], [0, 0]]) as view:
                with owner.call('gerbil-ascent-view-rows', view.reference(), module=oracle.VIEW) as public:
                    self.assertEqual(oracle.rows(public.graph), [[1, 1], [0, 0]])
                for function, module in (('gerbil-ascent-trrel-uf-view-lookup', oracle.UF),
                                         ('gerbil-ascent-view-rows', oracle.VIEW)):
                    with owner.call(function, view.reference(), [], [], module=module) as public:
                        self.assertEqual(oracle.rows(public.graph), [[0, 0], [1, 1]])
