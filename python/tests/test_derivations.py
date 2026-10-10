# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import unittest
from ascent_engine.derivations import normalize_contract,components,canonical_rule


class DerivationStructure(unittest.TestCase):
    def test_relaxed_head_surface_preserves_meaning_and_caller_input(self):
        atom={'relation':'answer','terms':[{'var':'x'}]}
        original={'rules':[{'head':atom,'body':[atom]}]}
        value=normalize_contract(original)
        self.assertEqual(value['rules'][0]['head'],[atom])
        self.assertIsInstance(original['rules'][0]['head'],dict)
        self.assertEqual(value['relations'],[])

    def test_recursive_and_multihead_dependencies_stay_atomic(self):
        def atom(n):return {'relation':n,'terms':[]}
        p={'relations':[{'name':n,'source':False} for n in ('reach','answer','left','right')],
           'rules':[{'head':[atom('reach')],'body':[atom('reach')]},
                    {'head':[atom('answer')],'body':[atom('reach')]},
                    {'head':[atom('left'),atom('right')],'body':[atom('reach')]}]}
        groups=components(p)
        self.assertIn(['left','right'],groups)
        self.assertLess(groups.index(['reach']),groups.index(['answer']))

    def test_alpha_renaming_preserves_dependency_fingerprint(self):
        def rule(a,b):return {'head':[{'relation':'reach','terms':[{'var':a},{'var':b}]}],
                             'body':[{'relation':'edge','terms':[{'var':a},{'var':b}]}]}
        self.assertEqual(canonical_rule(rule('x','y')),canonical_rule(rule('a','z')))


if __name__=='__main__':unittest.main()
