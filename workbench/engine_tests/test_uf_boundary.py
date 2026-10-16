# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Independent closure oracle against the fixed algorithm C ABI."""
import unittest
from ascent import Engine, EngineError


def closure(edges):
    nodes = {n for edge in edges for n in edge}
    adjacency = {n: set() for n in nodes}
    for a, b in edges:
        adjacency[a].add(b)
    answer = set()
    for start in nodes:
        pending, seen = [start], set()
        while pending:
            node = pending.pop()
            if node in seen:
                continue
            seen.add(node)
            pending.extend(adjacency[node] - seen)
        answer.update((start, end) for end in seen)
    return answer


class UFBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = Engine()

    @classmethod
    def tearDownClass(cls):
        cls.engine.close()

    def exercise(self, edges, tail):
        with self.engine.reachability() as state:
            count = sum(state.insert(edge, budget=100000) for edge in edges)
            expected_before = closure(edges)
            self.assertEqual(count, len(expected_before))
            with state.freeze() as before:
                resources = state.resources()
                expected_after = closure(edges + [tail])
                needed = len(expected_after - expected_before)
                self.assertGreater(needed, 0)
                with self.assertRaises(EngineError):
                    state.insert(tail, budget=needed - 1)
                self.assertEqual(state.resources(), resources)
                self.assertEqual(state.insert(tail, budget=needed), needed)
                self.assertTrue(state.validate())
                actual = before.rows()
                self.assertEqual(len(actual), len(expected_before))
                self.assertEqual(set(map(tuple, actual)), expected_before)
                with state.freeze() as current:
                    actual = current.rows()
                    self.assertEqual(len(actual), len(expected_after))
                    self.assertEqual(set(map(tuple, actual)), expected_after)

    def test_existing_endpoint_bridge(self):
        self.exercise([[i, i+1] for i in range(64)] + [[i, i+1] for i in range(65, 129)], [64, 65])

    def test_partial_scc_and_surviving_boundary(self):
        self.exercise([[i, i+1] for i in range(96)], [80, 16])

    def test_complete_scc_releases_root_arcs(self):
        self.exercise([[i, i+1] for i in range(96)], [96, 0])

    def test_scalar_weighted_frontier_and_retained_publication(self):
        for heavy_source in (False, True):
            edges = [[i, i+1] for i in range(64)] + [[i, i+1] for i in range(65, 129)]
            edges += ([[48, 16]] if heavy_source else []) + [[113, 81]]
            tail = [64, 65]
            with self.subTest(heavy_source=heavy_source), self.engine.reachability() as state:
                for edge in edges:
                    state.insert(edge, budget=100000)
                expected = closure(edges + [tail]) - closure(edges)
                physical = state.resources()
                with state.freeze() as before:
                    with self.assertRaises(EngineError):
                        state.insert(tail, budget=len(expected)-1)
                    self.assertEqual(state.resources(), physical)
                    self.assertEqual(state.insert(tail, budget=len(expected)), len(expected))
                    with state.freeze() as frontier:
                        rows = frontier.difference(before, budget=len(expected))
                        self.assertEqual(len(rows), len(expected))
                        self.assertEqual(set(map(tuple, rows)), expected)
                        self.assertEqual(state.insert(tail[::-1], budget=100000),
                            len(closure(edges+[tail,tail[::-1]])-closure(edges+[tail])))
                        self.assertEqual(frontier.difference(before, budget=len(expected)), rows)
                self.assertTrue(state.validate())
