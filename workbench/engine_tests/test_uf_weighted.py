"""Independent weighted UF export/query refinement through actual API and ABI."""
import unittest
from ascent import EngineError
import test_uf_materialization as oracle

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
        before_truth, after_truth = (oracle.closure(edges), oracle.closure(edges + tail))
        with self.engine.reachability() as state:
            reference = state
            for edge in edges:
                reference.insert(edge, budget=200000)
                pass
            with reference.freeze() as before:
                held = before
                result = held.rows()
                before_order = result
                for edge in tail:
                    reference.insert(edge, budget=200000)
                    pass
                with reference.freeze() as after:
                    current = after
                    for view, truth in ((held, before_truth), (current, after_truth)):
                        for row in ([23, 23], [24, 23], [23, 24], [999, 0], [0, 999]):
                            result = view.contains(row)
                            self.assertEqual(result, tuple(row) in truth)
                    result = current.rows()
                    after_order = result
                    delta = current.difference(held, budget=len(after_truth - before_truth))
                    actual = delta
                    self.assertEqual(actual, [row for row in after_order if tuple(row) not in before_truth])
                    self.assertEqual(set(map(tuple, actual)), after_truth - before_truth)
                result = held.rows()
                self.assertEqual(result, before_order)

    def test_complete_points_keep_grouped_owners_and_repeated_tiny_reads(self):
        for grouped, groups, size in ((True, range(8), 4), (False, (None,), 3)):
            edges = [[g, i, (i + 1) % size] if grouped else [i, (i + 1) % size] for g in groups for i in range(size)]
            truth = {(g, a, b) if grouped else (a, b) for g in groups for a, b in oracle.closure([e[1:] for e in edges if e[0] == g] if grouped else edges)}
            with self.engine.reachability() as state:
                ref = state
                for edge in edges:
                    ref.insert(edge, budget=200000)
                    pass
                with ref.freeze() as cut:
                    held = cut
                    public = held.rows()
                    full = public
                    self.assertEqual(set(map(tuple, full)), truth)
                    columns = [0, 1, 2] if grouped else [0, 1]
                    keys = ([g, a, b] if grouped else [a, b] for g in groups for a, b in ((0, 2), (2, 0), (99, 1), (1, 99)))
                    queries = [(columns, key) for key in keys]
                    queries += [(list(reversed(cols)), list(reversed(key))) for cols, key in queries.copy()]
                    if grouped:
                        queries.append((columns, [99, 0, 1]))
                    for _ in range(4):
                        for cols, key in queries:
                            expected = [row for row in full if all((row[c] == v for c, v in zip(cols, key)))]
                            public = held.rows(cols, key)
                            self.assertEqual(public, expected)
                    public = held.rows()
                    self.assertEqual(public, full)

    def test_weighted_cut_survives_extension_and_retirement(self):
        edges = [[i, (i + 1) % 128] for i in range(128)]
        self.exercise(edges, [[127, 128], [128, 0]])

    def test_grouped_weighted_cut_keeps_both_scopes(self):
        edges = [[g, i, (i + 1) % 64] for g in (0, 7) for i in range(64)]
        self.exercise(edges, [[0, 63, 64], [7, 63, 64]], grouped=True)

    def test_bound_axes_match_full_closure_order(self):
        edges = [[i, (i + 1) % 96] for i in range(96)]
        with self.engine.reachability() as state:
            reference = state
            for edge in edges:
                reference.insert(edge, budget=200000)
                pass
            with reference.freeze() as frozen:
                held = frozen
                public = held.rows()
                full = public
                self.assertEqual(set(map(tuple, full)), oracle.closure(edges))
                self.assertEqual(len(full), len(set(map(tuple, full))))
                for columns, key in (([0, 1], [3, 2]), ([0, 1], [999, 2]), ([0], [0]), ([1], [0]), ([0], [999]), ([1, 0], [2, 1]), ([0, 0], [1, 2])):
                    with self.subTest(columns=columns, key=key):
                        public = held.rows(columns, key)
                        self.assertEqual(public, [row for row in full if all((row[column] == value for column, value in zip(columns, key)))])

    def test_grouped_composite_queries_keep_owner_and_repeat_constraints(self):
        edges = [[g, i, (i + 1) % 12] for g in (0, 7, 9) for i in range(12)]
        truth = {(g, a, b) for g in (0, 7, 9) for a, b in oracle.closure([e[1:] for e in edges if e[0] == g])}
        with self.engine.reachability() as state:
            reference = state
            for edge in edges:
                reference.insert(edge, budget=200000)
                pass
            with reference.freeze() as frozen:
                held = frozen
                public = held.rows()
                full = public
                self.assertEqual(set(map(tuple, full)), truth)
                for edge in ([7, 11, 12], [7, 12, 0]):
                    reference.insert(edge, budget=200000)
                    pass
                for columns, key in (([0, 1, 2], [7, 3, 2]), ([2, 0, 1, 0, 2], [2, 7, 3, 7, 2]), ([1, 2], [3, 2]), ([1, 2, 1], [3, 2, 3]), ([1, 2, 1], [3, 2, 4]), ([0, 0], [7, 9]), ([0, 1], [99, 3])):
                    expected = [row for row in full if all((row[c] == v for c, v in zip(columns, key)))]
                    for _ in range(2):
                        public = held.rows(columns, key)
                        self.assertEqual(public, expected)
                public = held.rows()
                self.assertEqual(public, full)

    def test_repeated_queries_keep_partial_owner_intersections_and_tiny_cuts(self):
        edges = [[g, i, (i + 1) % size] for g, size in enumerate((4, 2, 3, 4, 2, 3, 4, 5)) for i in range(size)]
        truth = {(g, a, b) for g in range(8) for a, b in oracle.closure([edge[1:] for edge in edges if edge[0] == g])}
        with self.engine.reachability() as state:
            reference = state
            for edge in edges:
                reference.insert(edge, budget=200000)
                pass
            with reference.freeze() as cut:
                held = cut
                with self.assertRaisesRegex(EngineError, 'column'):
                    held.rows([1, 1, 3], [3, 4, 2])
                    pass
                public = held.rows()
                full = public
                self.assertEqual(set(map(tuple, full)), truth)
                for edge in ([0, 3, 4], [0, 4, 0]):
                    reference.insert(edge, budget=200000)
                    pass
                queries = (([1, 2], [3, 2]), ([2, 1, 2, 1], [2, 3, 2, 3]), ([0, 1, 2], [3, 3, 2]), ([1, 2, 1], [3, 2, 1]), ([1, 2], [99, 2]), ([1, 2], [0, 1]), ([1, 2] * 8, [3, 2] * 8), ([1, 2] * 8 + [1], [3, 2] * 8 + [4]), ([0, 1, 0], [3, 2, 3]), ([1, 2], [4, 2]), ([1, 2] * 8, [4, 2] * 8))
                for _ in range(8):
                    for columns, key in queries:
                        expected = [row for row in full if all((row[c] == v for c, v in zip(columns, key)))]
                        public = held.rows(columns, key)
                        self.assertEqual(public, expected)
                public = held.rows()
                self.assertEqual(public, full)
        edges = [[g, c * 2 + i, c * 2 + (1 - i)] for g in range(3) for c in range(4) for i in range(2)]
        with self.engine.reachability() as state:
            reference = state
            for edge in edges:
                reference.insert(edge, budget=200000)
                pass
            with reference.freeze() as cut:
                held = cut
                public = held.rows()
                full = public
                truth = {(g, a, b) for g in range(3) for a, b in oracle.closure([edge[1:] for edge in edges if edge[0] == g])}
                self.assertEqual(set(map(tuple, full)), truth)
                for columns, key in (([2, 0, 1, 0, 2], [7, 1, 6, 1, 7]), ([0, 1, 0], [1, 6, 1]), ([0, 2, 0], [1, 7, 1]), ([0, 1, 2], [1, 6, 3])):
                    expected = [row for row in full if all((row[c] == v for c, v in zip(columns, key)))]
                    public = held.rows(columns, key)
                    self.assertEqual(public, expected)
        self.exercise([[0, 1], [1, 0]], [])
