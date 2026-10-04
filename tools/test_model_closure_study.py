# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Byte transport and provider-context discriminators; no semantic oracle."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

TOOLS=Path(__file__).resolve().parent
sys.path.insert(0,str(TOOLS))
from model_prediction_transport import prediction_from_output
spec=importlib.util.spec_from_file_location('closure_study',TOOLS/'model-closure-study.py')
study=importlib.util.module_from_spec(spec);spec.loader.exec_module(study)

class ByteTransport(unittest.TestCase):
    def test_literal_assertions_and_quotes_are_inert(self):
        for text in ['2',"'2",'(check-equal? result 2)',"(check-equal? result '(1 2))"]:
            self.assertEqual(prediction_from_output(text),text)
        self.assertIsNone(prediction_from_output('(check-equal? result (+ 1 2))'))
        self.assertIsNone(prediction_from_output("(check-equal? result '?)"))

    def test_conflicting_explicit_data_is_rejected_without_private_truth(self):
        self.assertIsNone(prediction_from_output("(check-equal? result '2)\n```scheme\n'3\n```"))
        self.assertIsNotNone(prediction_from_output("(check-equal? result '2)\n```scheme\n'2\n```"))

    def test_size_and_nesting_are_bounded(self):
        self.assertIsNone(prediction_from_output('x'*65537))
        self.assertIsNone(prediction_from_output('('*65+'2'+')'*65))

    def test_request_context_difference_is_only_real_computed_feedback(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            (root/'f-initial.input.ss').write_text('ACTUAL-INITIAL-SOURCE')
            (root/'f-transfer.input.ss').write_text('ACTUAL-TRANSFER-SOURCE')
            (root/'f-transfer.task.ss').write_text('ACTUAL-TRANSFER-TASK')
            initial={'f':{'raw':"'2",'nativeObservation':{'nativeDatum':'2','correct':True}}}
            plan={'model':'deepseek-flash','maxInputBytes':655360,'maxOutputTokens':8192}
            item={'family':'f','case':'f-transfer','reasoningEffort':'high'}
            history=study.request_for(plan,root,{**item,'arm':'transfer-history'},initial)
            feedback=study.request_for(plan,root,{**item,'arm':'transfer-feedback'},initial)
            self.assertEqual(history['input'][:2],feedback['input'][:2])
            self.assertEqual(history['input'][2]['content'],'ACTUAL-TRANSFER-TASK')
            self.assertEqual(feedback['input'][2]['content'],json.dumps(initial['f']['nativeObservation'],sort_keys=True)+'\nACTUAL-TRANSFER-TASK')
            self.assertEqual(set(history),{'model','input','reasoning','max_output_tokens','stream','store'})
            self.assertEqual([x['role'] for x in history['input']],['user','assistant','user'])
            fresh=study.request_for(plan,root,{**item,'arm':'transfer-fresh'},initial)
            self.assertEqual(fresh['input'],[{'role':'user','content':'ACTUAL-TRANSFER-SOURCE'}])
            self.assertFalse(fresh['store'])

    def test_frozen_input_limit_rejects_before_dispatch(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'f-initial.input.ss').write_text('TOO-LONG')
            with self.assertRaises(ValueError):
                study.request_for({'maxInputBytes':1},root,{'case':'f-initial','arm':'initial-none'}, {})

if __name__=='__main__':unittest.main()
