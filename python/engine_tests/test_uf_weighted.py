"""Independent weighted UF export/query refinement through actual API and ABI."""
import unittest
from ascent_engine import EngineError

import test_uf_materialization as oracle
from test_uf_boundary import decode


class UFWeightedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        oracle.UFMaterializationTests.setUpClass.__func__(cls)

    @classmethod
    def tearDownClass(cls):
        oracle.UFMaterializationTests.tearDownClass.__func__(cls)

    exercise = oracle.UFMaterializationTests.exercise

    def test_indexed_membership_and_complete_delta_keep_frozen_owner_truth(self):
        edges = [[i, (i + 1) % 24] for i in range(24)]
        tail = [[23, 24], [24, 0]]
        before_truth, after_truth = oracle.closure(edges), oracle.closure(edges + tail)
        with self.engine.module(oracle.UF) as owner:
            with owner.call('gerbil-ascent-trrel-uf-state') as state:
                reference = state.reference()
                for edge in edges:
                    with owner.call('gerbil-ascent-trrel-uf-count-insert!', reference, edge, 200000):
                        pass
                with owner.call('gerbil-ascent-trrel-uf-freeze', reference, True) as before:
                    held = before.reference()
                    with owner.call('gerbil-ascent-view-rows', held, module=oracle.VIEW) as result:
                        before_order = oracle.rows(result.graph)
                    for edge in tail:
                        with owner.call('gerbil-ascent-trrel-uf-count-insert!', reference, edge, 200000):
                            pass
                    with owner.call('gerbil-ascent-trrel-uf-freeze', reference, True) as after:
                        current = after.reference()
                        for view, truth in ((held, before_truth), (current, after_truth)):
                            for row in ([23, 23], [24, 23], [23, 24], [999, 0], [0, 999]):
                                with owner.call('gerbil-ascent-view-contains?', view, row, module=oracle.VIEW) as result:
                                    self.assertEqual(decode(result.graph), tuple(row) in truth)
                        with owner.call('gerbil-ascent-view-rows', current, module=oracle.VIEW) as result:
                            after_order = oracle.rows(result.graph)
                        with owner.call('gerbil-ascent-view-difference', current, held,
                                        len(after_truth - before_truth), module=oracle.VIEW) as delta:
                            with owner.call('gerbil-ascent-view-rows', delta.reference(), module=oracle.VIEW) as result:
                                actual = oracle.rows(result.graph)
                            self.assertEqual(actual, [row for row in after_order if tuple(row) not in before_truth])
                            self.assertEqual(set(map(tuple, actual)), after_truth - before_truth)
                    with owner.call('gerbil-ascent-view-rows', held, module=oracle.VIEW) as result:
                        self.assertEqual(oracle.rows(result.graph), before_order)

    def test_complete_points_keep_grouped_owners_and_repeated_tiny_reads(self):
        for grouped, groups, size in ((True, range(8), 4), (False, (None,), 3)):
            edges = [[g, i, (i + 1) % size] if grouped else [i, (i + 1) % size]
                     for g in groups for i in range(size)]
            truth = {(g, a, b) if grouped else (a, b) for g in groups
                     for a, b in oracle.closure([e[1:] for e in edges if e[0] == g] if grouped else edges)}
            with self.engine.module(oracle.UF) as owner:
                with owner.call('gerbil-ascent-trrel-uf-state') as state:
                    ref = state.reference()
                    for edge in edges:
                        with owner.call('gerbil-ascent-trrel-uf-count-insert!', ref, edge, 200000):
                            pass
                    with owner.call('gerbil-ascent-trrel-uf-freeze', ref, True) as cut:
                        held = cut.reference()
                        with owner.call('gerbil-ascent-view-rows', held, module=oracle.VIEW) as public:
                            full = oracle.rows(public.graph)
                        self.assertEqual(set(map(tuple, full)), truth)
                        columns = [0, 1, 2] if grouped else [0, 1]
                        keys = ([g, a, b] if grouped else [a, b] for g in groups
                                for a, b in ((0, 2), (2, 0), (99, 1), (1, 99)))
                        queries = [(columns, key) for key in keys]
                        queries += [(list(reversed(cols)), list(reversed(key))) for cols, key in queries.copy()]
                        if grouped:
                            queries.append((columns, [99, 0, 1]))
                        for _ in range(4):
                            for cols, key in queries:
                                expected = [row for row in full if all(row[c] == v for c, v in zip(cols, key))]
                                with owner.call('gerbil-ascent-view-rows', held, cols, key,
                                                module=oracle.VIEW) as public:
                                    self.assertEqual(oracle.rows(public.graph), expected)
                        with owner.call('gerbil-ascent-view-rows', held, module=oracle.VIEW) as public:
                            self.assertEqual(oracle.rows(public.graph), full)

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
                    for columns, key in (([0, 1], [3, 2]), ([0, 1], [999, 2]),
                                         ([0], [0]), ([1], [0]), ([0], [999]),
                                         ([1, 0], [2, 1]), ([0, 0], [1, 2])):
                        with self.subTest(columns=columns, key=key):
                            with owner.call('gerbil-ascent-trrel-uf-view-lookup', held, columns, key) as public:
                                self.assertEqual(oracle.rows(public.graph), [row for row in full
                                    if all(row[column] == value for column, value in zip(columns, key))])

    def test_grouped_composite_queries_keep_owner_and_repeat_constraints(self):
        edges = [[g, i, (i + 1) % 12] for g in (0, 7, 9) for i in range(12)]
        truth = {(g, a, b) for g in (0, 7, 9) for a, b in oracle.closure([e[1:] for e in edges if e[0] == g])}
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
                    self.assertEqual(set(map(tuple, full)), truth)
                    # Retire/replace mutable owners before every composite read.
                    for edge in ([7, 11, 12], [7, 12, 0]):
                        with owner.call('gerbil-ascent-trrel-uf-count-insert!', reference, edge, 200000):
                            pass
                    for columns, key in (([0, 1, 2], [7, 3, 2]), ([2, 0, 1, 0, 2], [2, 7, 3, 7, 2]),
                                         ([1, 2], [3, 2]), ([1, 2, 1], [3, 2, 3]),
                                         ([1, 2, 1], [3, 2, 4]), ([0, 0], [7, 9]), ([0, 1], [99, 3])):
                        expected = [row for row in full if all(row[c] == v for c, v in zip(columns, key))]
                        for function, module in (('gerbil-ascent-trrel-uf-view-lookup', oracle.UF),
                                                 ('gerbil-ascent-view-rows', oracle.VIEW)):
                            with owner.call(function, held, columns, key, module=module) as public:
                                self.assertEqual(oracle.rows(public.graph), expected)
                    with owner.call('gerbil-ascent-view-rows', held, module=oracle.VIEW) as public:
                        self.assertEqual(oracle.rows(public.graph), full)

    def test_repeated_queries_keep_partial_owner_intersections_and_tiny_cuts(self):
        # Different group axes share values but not owners. The held plan must
        # survive later SCC retirement and repeated, reordered conditions.
        edges = [[g, i, (i + 1) % size] for g, size in enumerate((4, 2, 3, 4, 2, 3, 4, 5))
                 for i in range(size)]
        truth = {(g, a, b) for g in range(8)
                 for a, b in oracle.closure([edge[1:] for edge in edges if edge[0] == g])}
        with self.engine.module(oracle.UF) as owner:
            with owner.call('gerbil-ascent-trrel-uf-state') as state:
                reference = state.reference()
                for edge in edges:
                    with owner.call('gerbil-ascent-trrel-uf-count-insert!', reference, edge, 200000):
                        pass
                with owner.call('gerbil-ascent-trrel-uf-freeze', reference, True) as cut:
                    held = cut.reference()
                    with self.assertRaisesRegex(EngineError, 'invalid ASCENT UF view column'):
                        with owner.call('gerbil-ascent-view-rows', held, [1, 1, 3], [3, 4, 2],
                                        module=oracle.VIEW):
                            pass
                    with owner.call('gerbil-ascent-view-rows', held, module=oracle.VIEW) as public:
                        full = oracle.rows(public.graph)
                    self.assertEqual(set(map(tuple, full)), truth)
                    for edge in ([0, 3, 4], [0, 4, 0]):
                        with owner.call('gerbil-ascent-trrel-uf-count-insert!', reference, edge, 200000):
                            pass
                    queries = (([1, 2], [3, 2]), ([2, 1, 2, 1], [2, 3, 2, 3]),
                               ([0, 1, 2], [3, 3, 2]), ([1, 2, 1], [3, 2, 1]),
                               ([1, 2], [99, 2]), ([1, 2], [0, 1]),
                               ([1, 2] * 8, [3, 2] * 8),
                               ([1, 2] * 8 + [1], [3, 2] * 8 + [4]),
                               ([0, 1, 0], [3, 2, 3]),
                               ([1, 2], [4, 2]), ([1, 2] * 8, [4, 2] * 8))
                    for _ in range(8):
                        for columns, key in queries:
                            expected = [row for row in full if all(row[c] == v for c, v in zip(columns, key))]
                            with owner.call('gerbil-ascent-view-rows', held, columns, key,
                                            module=oracle.VIEW) as public:
                                self.assertEqual(oracle.rows(public.graph), expected)
                    with owner.call('gerbil-ascent-view-rows', held, module=oracle.VIEW) as public:
                        self.assertEqual(oracle.rows(public.graph), full)
        # Separate SCCs share a group but have distinct endpoint owners. Route
        # selection must preserve the independently computed closure and order.
        edges = [[g, c * 2 + i, c * 2 + (1 - i)]
                 for g in range(3) for c in range(4) for i in range(2)]
        with self.engine.module(oracle.UF) as owner:
            with owner.call('gerbil-ascent-trrel-uf-state') as state:
                reference = state.reference()
                for edge in edges:
                    with owner.call('gerbil-ascent-trrel-uf-count-insert!', reference, edge, 200000):
                        pass
                with owner.call('gerbil-ascent-trrel-uf-freeze', reference, True) as cut:
                    held = cut.reference()
                    with owner.call('gerbil-ascent-view-rows', held, module=oracle.VIEW) as public:
                        full = oracle.rows(public.graph)
                    truth = {(g, a, b) for g in range(3)
                             for a, b in oracle.closure([edge[1:] for edge in edges if edge[0] == g])}
                    self.assertEqual(set(map(tuple, full)), truth)
                    for columns, key in (([2, 0, 1, 0, 2], [7, 1, 6, 1, 7]),
                                         ([0, 1, 0], [1, 6, 1]),
                                         ([0, 2, 0], [1, 7, 1]),
                                         ([0, 1, 2], [1, 6, 3])):
                        expected = [row for row in full if all(row[c] == v for c, v in zip(columns, key))]
                        with owner.call('gerbil-ascent-view-rows', held, columns, key,
                                        module=oracle.VIEW) as public:
                            self.assertEqual(oracle.rows(public.graph), expected)
        # A single tiny owner uses the checked selection path, including repeats.
        self.exercise([[0, 1], [1, 0]], [])
