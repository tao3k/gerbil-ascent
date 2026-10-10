# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import unittest
from ascent_test_support import iterative_inference_study as loop
from ascent_test_support import inference_reuse_study as study


class IterativeEvidenceProtocol(unittest.TestCase):
    def test_first_round_treatment_cannot_silently_become_raw_fact_reasoning(self):
        for assisted,expected in [(False,'scan'),(True,'query')]:
            choices=loop.action_format(assisted,initial=True)['schema']['anyOf']
            self.assertEqual(len(choices),1)
            self.assertEqual(choices[0]['properties']['action']['enum'],[expected])

    def test_raw_scans_and_answer_only_projection_are_not_witness_queries(self):
        source=study.workload(0)['source']
        for query in ['cast','answer']:
            action={'contract':{'relations':[],'rules':[]},'queries':[query]}
            with self.assertRaises(ValueError):loop.evidence_program(source,action)

    def test_argument_notation_is_a_typed_protocol_error_with_repair_guidance(self):
        case=study.workload(3);contract=study.oracle_contract(case)
        with self.assertRaisesRegex(ValueError,'bare relation names'):
            loop.evidence_program(case['source'],{'contract':contract,'queries':['reachable(X,Y)']})

    def test_witness_projection_retains_the_model_requested_rule_body(self):
        case=study.workload(0);contract=study.oracle_contract(case)
        body=contract['rules'][0]['body']
        contract['relations']=[{'name':'witness','types':['Actor','Actor','Actor','Film','Director','Country']}]
        contract['rules']=[study.rule(study.atom('witness',*[study.var(n) for n in ('a','b','c','f','d','k')]),*body)]
        program=loop.evidence_program(case['source'],{'contract':contract,'queries':['witness']})
        self.assertEqual(program['rules'][0]['body'],body)
        self.assertEqual(program['queries'],['witness'])


if __name__=='__main__':unittest.main()
