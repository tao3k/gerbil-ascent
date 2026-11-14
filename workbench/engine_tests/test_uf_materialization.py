"""Complete immutable cut checks against an independent closure oracle."""
import unittest
from ascent import Engine
from test_uf_boundary import closure

class UFMaterializationTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.engine = Engine()

    @classmethod
    def tearDownClass(cls):
        cls.engine.close()

    def exercise(self, edges, tail, grouped=False):
        with self.engine.reachability() as state:
            reference = state
            for edge in edges:
                reference.insert(edge, budget=200000)
                pass
            with reference.freeze() as frozen:
                held = frozen
                public = held.rows()
                before = public
                expected = set()
                for group in sorted({edge[0] for edge in edges}) if grouped else [None]:
                    pairs = [edge[1:] for edge in edges if edge[0] == group] if grouped else edges
                    expected.update(((group, a, b) if grouped else (a, b) for a, b in closure(pairs)))
                self.assertEqual(set(map(tuple, before)), expected)
                self.assertEqual(len(before), len(expected))
                for edge in tail:
                    reference.insert(edge, budget=200000)
                    pass
                public = held.rows()
                self.assertEqual(public, before)
                columns, key = ([0, 1], [0, 0]) if grouped else ([0], [0])
                public = held.rows(columns, key)
                self.assertEqual(public, [row for row in before if all((row[column] == value for column, value in zip(columns, key)))])

    def test_dense_complete_rows(self):
        edges = [[i, (i + 1) % 128] for i in range(128)]
        self.exercise(edges, [[127, 128]])

    def test_grouped_complete_rows(self):
        edges = [[g, i, (i + 1) % 48] for g in (0, 7) for i in range(48)]
        self.exercise(edges, [[0, 47, 48], [7, 47, 48]], grouped=True)

    def test_sparse_cut_survives_full_scc_retirement(self):
        self.exercise([[i, i + 1] for i in range(48)], [[48, 0]])

    def test_compact_singletons_with_weighted_target_and_retained_export(self):
        edges = [[i, i + 1] for i in range(128)] + [[112, 32]]
        self.exercise(edges, [[128, 0]])

    def test_compacted_indexed_right_axis_and_repeated_query_constraints(self):
        edges = [[i, i + 1] for i in range(192)]
        with self.engine.reachability() as state:
            reference = state
            for edge in edges:
                reference.insert(edge, budget=200000)
                pass
            with reference.freeze() as frozen:
                held = frozen
                public = held.rows()
                full = public
                self.assertEqual(set(map(tuple, full)), closure(edges))
                for columns, key in (([1], [192]), ([1], [64]), ([1, 0], [192, 0]), ([1, 1], [192, 192]), ([1, 1], [192, 64]), ([1], [999])):
                    with self.subTest(columns=columns, key=key):
                        public = held.rows(columns, key)
                        self.assertEqual(public, [row for row in full if all((row[column] == value for column, value in zip(columns, key)))])
