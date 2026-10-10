# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import json
from pathlib import Path
import tempfile
import unittest
from ascent_test_support.repository_statistics import billing, repair_effort


def attempt(tokens, correct=False, submission=False):
    return {'providerCalls': 1, 'usage': {'input_tokens': 10, 'output_tokens': tokens+1, 'output_tokens_details': {'reasoning_tokens': tokens}}, 'correct': correct, 'actions': [{'name': 'submit_patch', 'result': {'verified': correct}}] if submission else []}


class RepositoryStatisticsTests(unittest.TestCase):
    def test_repair_includes_rejected_submission_until_first_acceptance(self):
        result = repair_effort([attempt(100), attempt(200, submission=True), attempt(300), attempt(400, True, True), attempt(999)])
        self.assertEqual(result['modelCalls'], 3)
        self.assertEqual(result['observedReasoningTokens'], 900)
        self.assertTrue(result['verified'])

    def test_failing_development_checks_start_repair_accounting(self):
        failed = attempt(200)
        failed['actions'] = [{'name': 'run_checks', 'result': {'allChecksPassed': False, 'verified': False}}]
        result = repair_effort([attempt(100), failed, attempt(300, True, True)])
        self.assertEqual(result['observedReasoningTokens'], 500)
        self.assertEqual(result['failureFeedbackKind'], 'run_checks')

    def test_interrupted_request_is_unknown_not_zero(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); episode = root/'task'; episode.mkdir()
            (episode/'1.request.json').write_text('{}')
            (episode/'2.request.json').write_text('{}')
            (episode/'1.response.json').write_text(json.dumps({'terminal': {'usage': {'input_tokens': 10, 'output_tokens': 3, 'output_tokens_details': {'reasoning_tokens': 2}}}}))
            result = billing(root)
            self.assertEqual(result['startedRequests'], 2)
            self.assertEqual(result['observedCalls'], 1)
            self.assertEqual(result['unknownUsageRequests'], ['task/2.request.json'])
            self.assertEqual(result['observedReasoningTokens'], 2)
            self.assertFalse(result['invoiceVerified'])


if __name__ == '__main__': unittest.main()
