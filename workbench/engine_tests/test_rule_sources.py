# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Native inert-source sessions retain execution, authority and lifecycle contracts."""
import os
import unittest
from ascent import Engine, EngineError, FactLimits

RULES = """(ascent-fragment
 (relation input ((x symbol?)))
 (relation blocked ((x symbol?)))
 (relation answer ((x symbol?)))
 ((answer X) <-- (input X) (not (blocked X))))"""

class RuleSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = (Engine(os.environ['ASCENT_ENGINE_LIBRARY'])
                      if os.environ.get('ASCENT_ENGINE_BACKEND') == 'abi' else Engine())
    @classmethod
    def tearDownClass(cls):
        cls.engine.shutdown()

    def test_full_projection_execution_and_withdrawal(self):
        with self.engine.open_rule_sources(RULES) as session:
            self.assertEqual(session.projection['status'], 'supported')
            self.assertEqual(len(session.projection['program']['rules']), 1)
            self.assertTrue(session.run(queries=['answer'])['complete'])
            session.replace({'input': [['a'], ['b']], 'blocked': [['b']]})
            self.assertEqual(session.run(queries=['answer'])['relations']['answer'], [['a']])
            session.replace({'input': [['b']], 'blocked': []})
            self.assertEqual(session.run(queries=['answer'])['relations']['answer'], [['b']])
        with self.assertRaises(ValueError):
            session.run()

    def test_authority_type_and_budget_rejections_preserve_generation(self):
        with self.engine.open_rule_sources(RULES, limits=FactLimits(input=2)) as session:
            self.assertTrue(session.run(queries=['answer'])['complete'])
            session.replace({'input': [['a']]})
            before = session.run(queries=['answer'])
            for update in ({'answer': [['forged']]}, {'input': [[17]]},
                           {'input': [['a'], ['b'], ['c']]}):
                with self.assertRaises(EngineError):
                    session.replace(update)
                after = session.run(queries=['answer'])
                self.assertEqual(after['relations'], before['relations'])
                self.assertEqual(after['sourceGeneration'], before['sourceGeneration'])

    def test_executable_and_malformed_sources_have_no_fallback(self):
        for text in ('(import :std/sugar)',
                     RULES.replace('(not (blocked X))', '(guard #t)'),
                     RULES.replace('(input X)', '(missing X)'),
                     RULES.replace('(input X)', '(input X X)')):
            with self.assertRaises(EngineError):
                self.engine.open_rule_sources(text)
        with self.engine.open_rule_sources(RULES) as session:
            self.assertTrue(session.run(queries=['answer'])['complete'])

    def test_recursive_multisource_matches_existing_native_catalog_execution(self):
        declarations = """(ascent-fragment
          (relation edge ((x symbol?) (y symbol?)))
          (relation path ((x symbol?) (y symbol?))))"""
        rules = """(ascent-fragment
          ((path X Y) <-- (edge X Y))
          ((path X Y) <-- (edge X Z) (path Z Y)))"""
        facts = {'edge': [['a', 'b'], ['b', 'c'], ['c', 'a']]}
        catalog = self.engine.read_rules(declarations, rules)
        for relation in catalog['relations']:
            relation['rows'] = facts.get(relation['name'], [])
        with self.engine.open({**catalog, 'queries': ['path']}) as control:
            expected = control.run()['relations']['path']
        with self.engine.open_rule_sources(declarations, rules) as session:
            self.assertTrue(session.run(queries=['path'])['complete'])
            session.replace(facts)
            observed = session.run(queries=['path'])
            self.assertTrue(observed['complete'])
            self.assertCountEqual(observed['relations']['path'], expected)
            self.assertEqual(len(expected), 9)

    def test_general_dsl_guards_keep_projection_gap_and_native_answers(self):
        source = '''(ascent-fragment
          (relation input ((x integer?))) (relation output ((x integer?)))
          ((output X) <-- (input X) (if (X) (and (>= X 0) (<= (+ X 1) 2)))))'''
        with self.engine.open_sources(source) as session:
            self.assertEqual(session.projection['status'], 'unsupported')
            self.assertTrue(session.run(queries=['output'])['complete'])
            session.replace({'input': [[-1], [0], [1], [2]]})
            observed = session.run(queries=['output'])
            self.assertCountEqual(observed['relations']['output'], [[0], [1]])
            with self.assertRaises(EngineError):
                session.replace({'input': [['invalid']]})
            self.assertEqual(session.run(queries=['output'])['relations'], observed['relations'])
            session.replace({'input': [[2]]})
            self.assertEqual(session.run(queries=['output'])['relations']['output'], [])

    def test_general_dsl_short_circuit_preserves_scheme_truth_and_boolean_admission(self):
        template = '''(ascent-fragment
          (relation input ((x integer?))) (relation output ((x integer?)))
          ((output X) <-- (input X) (if (X) EXPRESSION)))'''
        for expression, answer in [('(and #f (even? "invalid"))', []),
                                   ('(or #t (even? "invalid"))', [[0]]),
                                   ('(and)', [[0]]), ('(or)', [])]:
            with self.engine.open_sources(template.replace('EXPRESSION', expression)) as session:
                session.run(queries=['output'])
                session.replace({'input': [[0]]})
                self.assertEqual(session.run(queries=['output'])['relations']['output'], answer)
        with self.engine.open_sources(template.replace('EXPRESSION', '(or 0 (even? "invalid"))')) as session:
            session.run(queries=['output'])
            before = session.run(queries=['output'])
            with self.assertRaisesRegex(EngineError, 'guard must return a boolean'):
                session.replace({'input': [[0]]})
            after = session.run(queries=['output'])
            self.assertEqual(after['relations'], before['relations'])
            self.assertEqual(after['sourceGeneration'], before['sourceGeneration'])

    def test_general_dsl_wide_guard_retains_upstream_macro_language(self):
        source = '''(ascent-fragment
          (relation input ((a integer?) (b integer?) (c integer?) (d integer?)))
          (relation output ((a integer?)))
          ((output A) <-- (input A B C D) (if (A B C D) (and (<= A B) (<= C D)))))'''
        with self.engine.open_sources(source) as session:
            session.run(queries=['output'])
            session.replace({'input': [[1, 2, 3, 4], [2, 1, 3, 4]]})
            self.assertEqual(session.run(queries=['output'])['relations']['output'], [[1]])

    def test_general_dsl_multisource_composition_retains_recursive_closure(self):
        declarations = '''(ascent-fragment
          (relation edge ((x symbol?) (y symbol?)))
          (relation path ((x symbol?) (y symbol?))))'''
        rules = '''(ascent-fragment
          ((path X Y) <-- (edge X Y))
          ((path X Y) <-- (edge X Z) (path Z Y)))'''
        with self.engine.open_sources(declarations, rules) as session:
            self.assertEqual(session.projection['status'], 'supported')
            session.run(queries=['path'])
            session.replace({'edge': [['a', 'b'], ['b', 'c'], ['c', 'a']]})
            self.assertCountEqual(session.run(queries=['path'])['relations']['path'],
                                  [[a, b] for a in ['a', 'b', 'c'] for b in ['a', 'b', 'c']])
            session.replace({'edge': [['a', 'b']]})
            self.assertEqual(session.run(queries=['path'])['relations']['path'], [['a', 'b']])
