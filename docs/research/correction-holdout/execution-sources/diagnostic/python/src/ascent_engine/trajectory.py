# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Thin transport to the Scheme trajectory ledger, including unknown usage."""
import copy


class Trajectory:
    def __init__(self, engine, task, source_identity):
        self.engine = engine
        self.source_identity = source_identity
        self.handle = engine.request({'operation': 'trajectory', 'action': 'open',
                                      'task': task, 'sourceIdentity': source_identity})['trajectory']
        self.sequence = 0
        self.last_failure = None
        self.closed = None

    def append(self, kind, *, event_id=None, **fields):
        if self.closed is not None:
            raise ValueError('trajectory is closed')
        self.sequence += 1
        event_id = event_id or f'event:{self.sequence}'
        event = {'id': event_id, 'kind': kind, 'sourceIdentity': self.source_identity,
                 **copy.deepcopy(fields)}
        result = self.engine.request({'operation': 'trajectory', 'action': 'append',
                                      'trajectory': self.handle, 'event': event})
        return event_id, result

    def model_call(self, call_id, round, usage=None, repair_of=None):
        # output_tokens includes reasoning; do not add thinking a second time.
        normalized = {}
        if usage:
            for external, internal in (('input_tokens', 'inputTokens'), ('output_tokens', 'outputTokens')):
                if usage.get(external) is not None:
                    normalized[internal] = usage[external]
            thinking = (usage.get('output_tokens_details') or {}).get('reasoning_tokens')
            if thinking is not None:
                normalized['thinkingTokens'] = thinking
        fields = {'round': round, 'usage': normalized}
        repair = repair_of or self.last_failure
        if repair is not None:
            fields['repairOf'] = repair
        return self.append('model-call', event_id=f'call:{call_id}', **fields)[1]

    def evidence(self, feedback):
        if feedback['sourceIdentity'] != self.source_identity:
            raise ValueError('evidence belongs to another source')
        return self.append('evidence', resultReference=feedback['resultReference'],
                           pathIdentity=feedback['pathIdentity'],
                           reusedComponents=feedback['reusedComponents'],
                           freshComponents=feedback['freshComponents'],
                           retainedCompleted=feedback['retainedCompleted'])[1]

    def direct_answer(self, reference):
        return self.append('direct-answer', resultReference=reference)[1]

    def verify(self, correct, verifier, *, round=None, candidate=None, scope='task'):
        fields = {'correct': correct, 'verifier': verifier, 'candidate': candidate, 'scope': scope}
        if round is not None:
            fields['round'] = round
        event, result = self.append('verification', **fields)
        self.last_failure = None if correct else event
        return result

    def invalidate(self, next_source_identity, reason='source-replaced'):
        _, result = self.append('invalidate', nextSourceIdentity=next_source_identity, reason=reason)
        self.source_identity = next_source_identity
        self.last_failure = None
        return result

    def snapshot(self):
        if self.closed is not None:
            return copy.deepcopy(self.closed)
        return self.engine.request({'operation': 'trajectory', 'action': 'snapshot',
                                    'trajectory': self.handle})

    def close(self, reason='complete'):
        if self.closed is None:
            self.closed = self.engine.request({'operation': 'trajectory', 'action': 'close',
                                              'trajectory': self.handle, 'reason': reason})
        return copy.deepcopy(self.closed)

    def __enter__(self):
        return self

    def __exit__(self, *exception):
        self.close('exception' if exception[0] else 'complete')
