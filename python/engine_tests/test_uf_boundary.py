# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Python oracle against actual exported UF procedures in both ABI bindings."""
import os
import unittest
import hashlib
from pathlib import Path
from ascent_engine import Engine, EngineError

UF = ':gerbil-ascent/table/trrel-uf'
VIEW = ':gerbil-ascent/core/relation-view'


def decode(graph):
    """Decode only scalar/vector resource observations used by these controls."""
    nodes = {node['id']: node for node in graph['nodes']}

    def item(value):
        value = nodes[value['ref']] if 'ref' in value else value
        if value['type'] == 'number':
            return int(value['value'])
        if value['type'] == 'boolean':
            return value['value']
        if value['type'] == 'vector':
            return [item(cell) for cell in value['items']]
        raise AssertionError(value['type'])
    return item(graph['root'])


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


def decode_rows(graph):
    """Walk the actual row spine without recursive Python list expansion."""
    nodes = {node['id']: node for node in graph['nodes']}

    def dereference(value):
        return nodes[value['ref']] if 'ref' in value else value

    def spine(value):
        while True:
            value = dereference(value)
            if value['type'] == 'null':
                return
            if value['type'] != 'pair':
                raise AssertionError(value['type'])
            yield value['car']
            value = value['cdr']

    answer = []
    for row in spine(graph['root']):
        columns = []
        for cell in spine(row):
            cell = dereference(cell)
            if cell['type'] != 'number':
                raise AssertionError(cell['type'])
            columns.append(int(cell['value']))
        if len(columns) != 2:
            raise AssertionError(columns)
        answer.append(columns)
    return answer


class UFBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = Engine(os.environ.get('ASCENT_NATIVE_LIBRARY'))
        receipt = cls.engine.build_receipt or {}
        producer = receipt.get('producerBuild', receipt)
        expected = hashlib.sha256((Path(__file__).resolve().parents[2] / 'table/trrel-uf.ss').read_bytes()).hexdigest()
        actual = producer.get('sourceInputs', {}).get('table/trrel-uf.ss')
        if actual != expected:
            raise AssertionError('UF producer source identity differs from this checkout')
        print(f'UF-ORACLE-BACKEND {cls.engine.backend} UF-SHA256 {actual}', flush=True)

    @classmethod
    def tearDownClass(cls):
        cls.engine.shutdown()

    def exercise(self, edges, tail):
        with self.engine.module(UF) as owner:
            with owner.call('gerbil-ascent-trrel-uf-state') as state:
                reference = state.reference()
                count = 0
                for edge in edges:
                    with owner.call('gerbil-ascent-trrel-uf-count-insert!', reference, edge, 100000) as value:
                        count += decode(value.graph)
                expected_before = closure(edges)
                self.assertEqual(count, len(expected_before))
                with owner.call('gerbil-ascent-trrel-uf-freeze', reference, False) as frozen:
                    before = frozen.reference()
                    with owner.call('gerbil-ascent-trrel-uf-resource-observation', reference) as physical:
                        resources = decode(physical.graph)
                    expected_after = closure(edges + [tail])
                    needed = len(expected_after - expected_before)
                    self.assertGreater(needed, 0)
                    with self.assertRaisesRegex(EngineError, 'fact budget exceeded'):
                        owner.call('gerbil-ascent-trrel-uf-count-insert!', reference, tail, needed - 1)
                    with owner.call('gerbil-ascent-trrel-uf-resource-observation', reference) as physical:
                        self.assertEqual(decode(physical.graph), resources)
                    with owner.call('gerbil-ascent-trrel-uf-count-insert!', reference, tail, needed) as value:
                        self.assertEqual(decode(value.graph), needed)
                    with owner.call('gerbil-ascent-trrel-uf-validate', reference) as value:
                        self.assertTrue(decode(value.graph))
                    with owner.call('gerbil-ascent-view-rows', before, module=VIEW) as value:
                        actual = decode_rows(value.graph)
                        self.assertEqual(len(actual), len(expected_before))
                        self.assertEqual({tuple(row) for row in actual}, expected_before)
                    with owner.call('gerbil-ascent-trrel-uf-freeze', reference, False) as current:
                        with owner.call('gerbil-ascent-view-rows', current.reference(), module=VIEW) as value:
                            actual = decode_rows(value.graph)
                            self.assertEqual(len(actual), len(expected_after))
                            self.assertEqual({tuple(row) for row in actual}, expected_after)

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
            with self.subTest(heavy_source=heavy_source), self.engine.module(UF) as owner:
                with owner.call('gerbil-ascent-trrel-uf-state') as state:
                    ref = state.reference()
                    for edge in edges:
                        with owner.call('gerbil-ascent-trrel-uf-count-insert!', ref, edge, 100000):
                            pass
                    before = closure(edges)
                    expected = closure(edges + [tail]) - before
                    with owner.call('gerbil-ascent-trrel-uf-resource-observation', ref) as value:
                        physical = decode(value.graph)
                    with self.assertRaisesRegex(EngineError, 'fact budget exceeded'):
                        owner.call('gerbil-ascent-trrel-uf-insert!', ref, tail, len(expected)-1)
                    with owner.call('gerbil-ascent-trrel-uf-resource-observation', ref) as value:
                        self.assertEqual(decode(value.graph), physical)
                    with owner.call('gerbil-ascent-trrel-uf-insert!', ref, tail, len(expected)) as frontier:
                        with owner.call('gerbil-ascent-view-rows', frontier.reference(), module=VIEW) as value:
                            rows = decode_rows(value.graph)
                        self.assertEqual(len(rows), len(expected))
                        self.assertEqual({tuple(row) for row in rows}, expected)
                        with owner.call('gerbil-ascent-trrel-uf-count-insert!', ref, tail[::-1], 100000) as value:
                            self.assertEqual(decode(value.graph), len(closure(edges+[tail,tail[::-1]])-closure(edges+[tail])))
                        with owner.call('gerbil-ascent-view-rows', frontier.reference(), module=VIEW) as value:
                            self.assertEqual(decode_rows(value.graph), rows)
                    with owner.call('gerbil-ascent-trrel-uf-validate', ref) as value:
                        self.assertTrue(decode(value.graph))
