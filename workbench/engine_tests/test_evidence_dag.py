# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Actual Scheme Evidence DAG contracts through the compiled Library ABI/API."""
import copy
import os
import unittest

from ascent_engine import Engine, EngineError
from ascent_engine.derivations import components, canonical_rule, evidence_dag


def atom(name, variable='x'):
    return {'relation': name, 'terms': [{'var': variable}]}


def declaration(name, source=False, rows=None, kind='symbol'):
    return {'name': name, 'source': source, 'columns': [{'kind': kind}], 'rows': rows or []}


class EvidenceDagTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = (Engine(os.environ['ASCENT_ENGINE_LIBRARY'])
                      if os.environ.get('ASCENT_ENGINE_BACKEND') == 'abi' else Engine())

    @classmethod
    def tearDownClass(cls):
        cls.engine.shutdown()

    def slice(self, program, facts, queries):
        return self.engine.request({'operation': 'evidence-dag', 'action': 'slice',
                                    'program': program, 'facts': facts, 'queries': queries})

    def test_recursive_and_multihead_dependencies_stay_atomic(self):
        program = {'relations': [declaration(n) for n in ('reach', 'answer', 'left', 'right')],
                   'rules': [{'head': [atom('reach')], 'body': [atom('reach')]},
                             {'head': [atom('answer')], 'body': [atom('reach')]},
                             {'head': [atom('left'), atom('right')], 'body': [atom('reach')]}]}
        groups = components(self.engine, program)
        self.assertIn(['left', 'right'], groups)
        self.assertLess(groups.index(['reach']), groups.index(['answer']))

    def test_explicit_dag_preserves_recursive_component_and_topological_edges(self):
        program = {'relations': [declaration('input', True), declaration('reach'), declaration('answer')],
                   'rules': [{'head': [atom('reach')], 'body': [atom('input')]},
                             {'head': [atom('reach')], 'body': [atom('reach')]},
                             {'head': [atom('answer')], 'body': [atom('reach')]}]}
        dag = evidence_dag(self.engine, program)
        self.assertEqual([node['relations'] for node in dag['nodes']],
                         [['input'], ['reach'], ['answer']])
        self.assertTrue(dag['nodes'][1]['recursive'])
        positions = {node['id']:i for i,node in enumerate(dag['nodes'])}
        self.assertTrue(all(positions[edge['from']] < positions[edge['to']]
                            for edge in dag['edges']))

    def test_alpha_renaming_is_native_and_does_not_mutate_input(self):
        def rule(a, b):
            return {'head': [{'relation': 'reach', 'terms': [{'var': a}, {'var': b}]}],
                    'body': [{'relation': 'edge', 'terms': [{'var': a}, {'var': b}]}]}
        original = rule('x', 'y')
        saved = copy.deepcopy(original)
        self.assertEqual(canonical_rule(self.engine, original),
                         canonical_rule(self.engine, rule('a', 'z')))
        self.assertEqual(original, saved)

    def test_slice_keeps_negative_and_reducer_dependencies(self):
        program = {'relations': [declaration(n, True) for n in ('input', 'blocked', 'unrelated')]
                                + [declaration('answer')],
                   'rules': [{'head': [atom('answer')],
                              'body': [atom('input'), {**atom('blocked'), 'not': True}]}]}
        result = self.slice(program, {'input': [['a']], 'blocked': [], 'unrelated': [['b']]}, ['answer'])
        self.assertEqual([r['name'] for r in result['relations']], ['answer', 'blocked', 'input'])
        program['rules'][0]['body'] = [{'mode': 'reduce', 'operator': 'count',
                                      'output': 'x', 'inputs': [], 'relation': 'input', 'terms': []}]
        result = self.slice(program, {'input': [['a']]}, ['answer'])
        self.assertEqual([r['name'] for r in result['relations']], ['answer', 'input'])

    def test_slice_rejects_extra_rule_fields_and_bool_integer(self):
        program = {'relations': [declaration('input', True, kind='integer'), declaration('answer')],
                   'rules': [{'head': [atom('answer')], 'body': [atom('input')], 'waiver': True}]}
        with self.assertRaises(EngineError):
            self.slice(program, {'input': [[1]]}, ['answer'])
        del program['rules'][0]['waiver']
        with self.assertRaises(EngineError):
            self.slice(program, {'input': [[True]]}, ['answer'])

    def test_slice_rejects_missing_sources_and_undefined_or_source_heads(self):
        program = {'relations': [declaration('input', True), declaration('answer')],
                   'rules': [{'head': [atom('answer')], 'body': [atom('input')]}]}
        with self.assertRaises(EngineError):
            self.slice(program, {}, ['answer'])
        with self.assertRaises(EngineError):
            self.slice({**program, 'rules': []}, {'input': []}, ['answer'])
        program['rules'][0]['head'] = [atom('input')]
        with self.assertRaises(EngineError):
            self.slice(program, {'input': []}, ['input'])

    def test_query_dag_rejects_changed_source_before_reuse(self):
        source = declaration('input', True, [['a']])
        program = {'relations': [source, declaration('answer')],
                   'rules': [{'head': [atom('answer')], 'body': [atom('input')]}],
                   'queries': ['answer']}
        request = {'operation': 'evidence-dag', 'action': 'query', 'program': program,
                   'trusted': {'input': copy.deepcopy(source)}, 'sources': ['input'],
                   'sourceIdentity': 'actual-host-bound-source', 'retain': True, 'certificates': {}}
        dag = self.engine.request(request)
        self.assertEqual(dag['mapping'], {})
        self.assertEqual(len(dag['fresh']), 1)
        program['relations'][0]['rows'] = []
        with self.assertRaises(EngineError):
            self.engine.request(request)

    def test_query_dag_reuses_exact_completed_alias_and_retains_all_sources(self):
        source = declaration('input', True, [['a']])
        program = {'relations': [source, declaration('answer')],
                   'rules': [{'head': [atom('answer')], 'body': [atom('input')]}], 'queries': ['answer']}
        request = {'operation': 'evidence-dag', 'action': 'query', 'program': program,
                   'trusted': {'input': source}, 'sources': ['input'],
                   'sourceIdentity': 'same-bound-source', 'retain': True, 'certificates': {}}
        first = self.engine.request(request)
        request['certificates'][first['keys']['answer']] = {'answer': 'input'}
        rejected_alias = self.engine.request(request)
        self.assertFalse(rejected_alias['mapping'])
        self.assertFalse(rejected_alias['reused'])
        request['trusted']['completed_answer'] = declaration('completed_answer', True, [['a']])
        request['certificates'][first['keys']['answer']] = {'answer': 'completed_answer'}
        second = self.engine.request(request)
        self.assertEqual(second['mapping'], {'answer': 'completed_answer'})
        self.assertEqual(second['lowered']['rules'], [])
        self.assertEqual(second['lowered']['queries'], ['completed_answer'])
        self.assertEqual([r['name'] for r in second['lowered']['relations']], ['input'])
        request['sourceIdentity'] = 'changed-bound-source'
        self.assertFalse(self.engine.request(request)['reused'])

    def test_capability_is_public_and_request_unknown_fields_are_rejected(self):
        self.assertIn('evidence-dag', self.engine.request({'operation': 'describe'})['operations'])
        with self.assertRaises(EngineError):
            self.engine.request({'operation': 'evidence-dag', 'action': 'components',
                                 'program': {'relations': [], 'rules': []}, 'waiver': True})


if __name__ == '__main__':
    unittest.main()
