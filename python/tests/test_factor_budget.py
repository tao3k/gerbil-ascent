# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import pytest
from ascent_test_support.factor_budget import charge_usage, input_reserve

def test_gross_input_includes_cache_hits_and_reasoning_is_not_double_counted():
    usage={'input_tokens':1000,'input_tokens_details':{'cached_tokens':900},
           'output_tokens':500,'output_tokens_details':{'reasoning_tokens':400},'total_tokens':1500}
    assert charge_usage(usage)==1500
    assert charge_usage(usage)+charge_usage(usage)==3000

@pytest.mark.parametrize('usage',[None,{}, {'input_tokens':True,'output_tokens':10},
    {'input_tokens':10,'output_tokens':20,'total_tokens':29},
    {'input_tokens':10,'output_tokens':20,'output_tokens_details':{'reasoning_tokens':21}}])
def test_unknown_or_inconsistent_usage_cannot_be_admitted(usage):
    with pytest.raises(ValueError):charge_usage(usage)

def test_retransmitted_reasoning_increases_next_call_input_reservation():
    request={'input':[{'role':'user','content':'优化'}]}
    initial=input_reserve(request)
    request['input'].append({'type':'reasoning','text':'x'*8192})
    assert input_reserve(request)>initial+8192
