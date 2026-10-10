# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

from ascent_test_support import inference_reuse_study as study


class InferenceReuse(unittest.TestCase):
    def test_incomplete_provider_contract_cannot_enter_scheme_admission(self):
        for value in (None,{}, {'relations':[],'rules':[]}):
            with self.assertRaisesRegex(ValueError,'output_budget_exhausted'):
                study.completed_contract(value,'output_budget_exhausted')
        with self.assertRaisesRegex(ValueError,'not a contract object'):
            study.completed_contract(None,'completed_ungraded')

    def test_holdout_intent_has_no_source_rows_or_oracle_answers(self):
        all_entities=set()
        for i in range(4):
            case=study.workload(i);source=case['source']
            public=json.loads(study.request(case,source,'compact')['input'][0]['content'].split('\n',1)[1])
            self.assertNotIn('facts',public);self.assertNotIn('domains',public)
            self.assertNotIn('gold',public);self.assertNotIn('expected',public)
            entities={x for values in source['domains'].values() for x in values}
            self.assertFalse(entities & all_entities);all_entities |= entities
            self.assertFalse(any(x in json.dumps(public) for x in entities))

    def test_withdrawals_change_answers_without_mutating_source(self):
        for i in range(4):
            case=study.workload(i);before=copy.deepcopy(case['source'])
            current=study.updated(case)
            self.assertNotEqual(study.expected(case,current),study.expected(case,before))
            self.assertEqual(case['source'],before)
            self.assertNotEqual(study.identity(current),study.identity(before))

    def test_source_heads_and_derived_declaration_collisions_are_rejected(self):
        case=study.workload(0)
        for name in study.SCHEMA:
            with self.assertRaises(ValueError):
                study.program(case['source'],{'relations':[], 'rules':[study.rule(study.atom(name))]})
            with self.assertRaises(ValueError):
                study.program(case['source'],{'relations':[{'name':name,'types':['Actor']}], 'rules':[]})

    def test_actual_scheme_repeat_and_source_update_match_fresh_evaluation(self):
        code='''
from ascent_engine import Engine
from ascent_test_support import inference_reuse_study as s
import os
with Engine(os.environ.get('ASCENT_ENGINE_LIBRARY',s.ROOT/'.gerbil/lib/libascent.dylib')) as e:
    for i in range(4):
        case=s.workload(i);source=case['source'];contract=s.oracle_contract(case)
        with e.open(s.program(source,contract)) as retained:
            initial=retained.run()
            assert initial['complete'] and sorted(initial['relations']['answer'])==s.expected(case,source)
            assert retained.run(0)==initial
            current=s.updated(case)
            retained.replace([{'relation':n,'rows':r} for n,r in current['rows'].items()])
            result=retained.run()
            assert result['complete'] and sorted(result['relations']['answer'])==s.expected(case,current)
            assert result['relations']['answer']!=initial['relations']['answer']
            with e.open(s.program(current,contract)) as fresh:
                assert sorted(fresh.run()['relations']['answer'])==sorted(result['relations']['answer'])
            assert retained.run(0)==result
            print('RETAINED-SOURCE-UPDATE-OK',case['name'],flush=True)
'''
        subprocess.run([sys.executable,'-u','-'],input=code,text=True,check=True,
                       env={**os.environ,'PYTHONPATH':str(study.ROOT/'python/src')})

    def test_finite_recursive_source_correspondence_and_stale_answer_control(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)/'receipt.json'
            library=os.environ.get('ASCENT_ENGINE_LIBRARY',study.ROOT/'.gerbil/lib/libascent.dylib')
            subprocess.run([sys.executable,'-u','-m','ascent_test_support.retained_inference',
                str(study.ROOT/'t/qualification/fixtures/inference-reuse/conformance.json'),
                str(library),str(output)],check=True)
            receipt=json.loads(output.read_text())
            self.assertEqual(receipt['observations'],32)
            self.assertEqual(receipt['changedSourceStaleAnswerFaultsDetected'],8)
            self.assertEqual(receipt['publishedSubgoalExtensionObservations'],32)


if __name__=='__main__':unittest.main()
