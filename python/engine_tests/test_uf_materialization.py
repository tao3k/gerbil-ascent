"""Independent complete UF export checks through actual native API and ABI."""
import hashlib
import os
from pathlib import Path
import unittest

from ascent_engine import Engine
from test_uf_boundary import closure

UF = ':gerbil-ascent/table/trrel-uf'
VIEW = ':gerbil-ascent/core/relation-view'


def rows(graph):
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

    return [[int(dereference(cell)['value']) for cell in spine(row)]
            for row in spine(graph['root'])]


class UFMaterializationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = Engine(os.environ.get('ASCENT_NATIVE_LIBRARY'))
        receipt = cls.engine.build_receipt or {}
        producer = receipt.get('producerBuild', receipt)
        for source in ('core/relation-view.ss', 'program/view-state.ss', 'table/trrel-uf.ss'):
            path = Path(__file__).resolve().parents[2] / source
            expected = hashlib.sha256(path.read_bytes()).hexdigest()
            if producer.get('sourceInputs', {}).get(source) != expected:
                raise AssertionError(f'producer source identity differs: {source}')
        print(f'UF-MATERIALIZATION-ORACLE {cls.engine.backend}', flush=True)

    @classmethod
    def tearDownClass(cls):
        cls.engine.shutdown()

    def exercise(self, edges, tail, grouped=False):
        with self.engine.module(UF) as owner:
            with owner.call('gerbil-ascent-trrel-uf-state') as state:
                reference = state.reference()
                for edge in edges:
                    with owner.call('gerbil-ascent-trrel-uf-count-insert!', reference, edge, 200000):
                        pass
                with owner.call('gerbil-ascent-trrel-uf-freeze', reference, True) as frozen:
                    held = frozen.reference()
                    with owner.call('gerbil-ascent-view-rows', held, module=VIEW) as public:
                        before = rows(public.graph)
                    expected = set()
                    for group in sorted({edge[0] for edge in edges}) if grouped else [None]:
                        pairs = [edge[1:] for edge in edges if edge[0] == group] if grouped else edges
                        expected.update((group, a, b) if grouped else (a, b)
                                        for a, b in closure(pairs))
                    self.assertEqual(set(map(tuple, before)), expected)
                    self.assertEqual(len(before), len(expected))
                    for edge in tail:
                        with owner.call('gerbil-ascent-trrel-uf-count-insert!', reference, edge, 200000):
                            pass
                    with owner.call('gerbil-ascent-view-rows', held, module=VIEW) as public:
                        self.assertEqual(rows(public.graph), before)
                    columns, key = ([0, 1], [0, 0]) if grouped else ([0], [0])
                    with owner.call('gerbil-ascent-trrel-uf-view-lookup', held, columns, key) as public:
                        self.assertEqual(rows(public.graph), [row for row in before
                            if all(row[column] == value for column, value in zip(columns, key))])

    def test_dense_complete_rows(self):
        edges = [[i, (i + 1) % 128] for i in range(128)]
        self.exercise(edges, [[127, 128]])

    def test_grouped_complete_rows(self):
        edges = [[g, i, (i + 1) % 48] for g in (0, 7) for i in range(48)]
        self.exercise(edges, [[0, 47, 48], [7, 47, 48]], grouped=True)

    def test_sparse_cut_survives_full_scc_retirement(self):
        self.exercise([[i, i + 1] for i in range(48)], [[48, 0]])
