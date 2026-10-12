"""Independent weighted UF export/query refinement through actual API and ABI."""
import unittest

import test_uf_materialization as oracle


class UFWeightedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        oracle.UFMaterializationTests.setUpClass.__func__(cls)

    @classmethod
    def tearDownClass(cls):
        oracle.UFMaterializationTests.tearDownClass.__func__(cls)

    exercise = oracle.UFMaterializationTests.exercise

    def test_weighted_cut_survives_extension_and_retirement(self):
        edges = [[i, (i + 1) % 128] for i in range(128)]
        self.exercise(edges, [[127, 128], [128, 0]])

    def test_grouped_weighted_cut_keeps_both_scopes(self):
        edges = [[g, i, (i + 1) % 64] for g in (0, 7) for i in range(64)]
        self.exercise(edges, [[0, 63, 64], [7, 63, 64]], grouped=True)

    def test_bound_axes_match_full_closure_order(self):
        edges = [[i, (i + 1) % 96] for i in range(96)]
        with self.engine.module(oracle.UF) as owner:
            with owner.call('gerbil-ascent-trrel-uf-state') as state:
                reference = state.reference()
                for edge in edges:
                    with owner.call('gerbil-ascent-trrel-uf-count-insert!', reference, edge, 200000):
                        pass
                with owner.call('gerbil-ascent-trrel-uf-freeze', reference, True) as frozen:
                    held = frozen.reference()
                    with owner.call('gerbil-ascent-view-rows', held, module=oracle.VIEW) as public:
                        full = oracle.rows(public.graph)
                    self.assertEqual(set(map(tuple, full)), oracle.closure(edges))
                    self.assertEqual(len(full), len(set(map(tuple, full))))
                    for columns, key in (([0], [0]), ([1], [0]), ([0], [999]),
                                         ([1, 0], [2, 1]), ([0, 0], [1, 2])):
                        with self.subTest(columns=columns, key=key):
                            with owner.call('gerbil-ascent-trrel-uf-view-lookup', held, columns, key) as public:
                                self.assertEqual(oracle.rows(public.graph), [row for row in full
                                    if all(row[column] == value for column, value in zip(columns, key))])
