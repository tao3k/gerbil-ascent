# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Stateless Responses conversation with complete reasoning and paired tool IO."""
import copy
import json


class ResponseHistory:
    """Forward provider reasoning opaquely; Scheme validates external evidence.

    All previous reasoning output items stay beside their assistant/tool-call
    output. Never replace them with a response id on a stateless backend.
    This class does not inspect, summarize or certify model reasoning text.
    """
    def __init__(self,question):
        self.items=[{'role':'user','content':question}]
        self.pending={};self.seen=set()

    def input(self):
        if self.pending:raise ValueError('every function call requires a paired output')
        return copy.deepcopy(self.items)

    def append_response(self,response):
        output=response.get('output')
        if not isinstance(output,list):raise ValueError('response output items required')
        if self.pending:raise ValueError('previous tool results are still pending')
        calls=[];new=set()
        for item in output:
            if item.get('type') not in ('reasoning','message','function_call'):
                raise ValueError('unsupported response output item')
            if item['type']=='function_call':
                call=item.get('call_id')
                if not isinstance(call,str) or not call or call in self.seen or call in new:
                    raise ValueError('tool call identity must be unique')
                new.add(call);calls.append(copy.deepcopy(item))
        self.items.extend(copy.deepcopy(output));self.seen.update(new)
        self.pending={call['call_id']:call for call in calls}
        return calls

    def append_result(self,call_id,result):
        if call_id not in self.pending:raise ValueError('unknown or already completed tool call')
        payload=json.dumps(result,sort_keys=True,separators=(',',':'))
        self.items.append({'type':'function_call_output','call_id':call_id,'output':payload})
        self.pending.pop(call_id)

    def append_feedback(self,result):
        if self.pending:raise ValueError('complete paired tool outputs before feedback')
        self.items.append({'role':'user','content':json.dumps(result,sort_keys=True)})

    @property
    def reasoning_items(self):return sum(item.get('type')=='reasoning' for item in self.items)
