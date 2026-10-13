# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import unittest
from unittest.mock import Mock
from ascent_engine.derivations import normalize_contract, evidence_dag, components, canonical_rule


class DerivationStructure(unittest.TestCase):
    def test_dag_helpers_use_the_same_native_operation(self):
        engine=Mock()
        engine.request.return_value={'components':[['answer']], 'rule':{'body':[]}}
        program={'relations':[], 'rules':[]}
        evidence_dag(engine,program)
        self.assertEqual(engine.request.call_args.args[0],
                         {'operation':'evidence-dag','action':'graph','program':program})
        self.assertEqual(components(engine,program),[['answer']])
        self.assertEqual(canonical_rule(engine,{'body':[]}),{'body':[]})
        self.assertTrue(all(call.args[0]['operation']=='evidence-dag'
                            for call in engine.request.call_args_list))

    def test_relaxed_head_surface_preserves_meaning_and_caller_input(self):
        atom={'relation':'answer','terms':[{'var':'x'}]}
        original={'rules':[{'head':atom,'body':[atom]}]}
        value=normalize_contract(original)
        self.assertEqual(value['rules'][0]['head'],[atom])
        self.assertIsInstance(original['rules'][0]['head'],dict)
        self.assertEqual(value['relations'],[])


if __name__=='__main__':unittest.main()
