# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Byte transport and provider-context discriminators; no semantic oracle."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1] / 'src'))
from ascent_test_support import model_study as study

class ProviderByteContext(unittest.TestCase):
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
