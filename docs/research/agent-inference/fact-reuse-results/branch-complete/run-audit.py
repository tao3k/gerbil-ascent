"""Read-only model protocol/usage/grade audit. No provider calls or relabeling."""
import sys,json,hashlib
from pathlib import Path
build=Path(sys.argv[1]).resolve();root=build/'source';sys.path[:0]=[str(root/'python/src'),str(build/'api' if (build/'api').exists() else build/'frozen/api-runtime')]
from ascent_test_support.evidence_chain_study import shared_check,shared_truth,branch_grade,branch_submission_context
frozen=build/'frozen';run=build/'run';plan=shared_check(frozen);rows=json.loads((run/'ledger.json').read_text());outcomes=[]
for row in rows:
    task=plan['tasks'][row['case']];gross=0;previous={};visible=0;opaque=[]
    for c in row['calls']:
        folder=run/'calls'/f"{row['case']}-{row['arm']}"/f"{c['turn']}-{c['step']}"
        req=json.loads((folder/'request.json').read_text());meta=json.loads((folder/'response.json').read_text());terminal=meta.get('terminal') or {}
        assert not req.get('instructions') and req['tools']==[plan['tool']] and req['tool_choice']==('auto' if c['step']==0 else {'type':'function','name':'submit_selection'})
        assert req['reasoning']=={'effort':plan['reasoningEffort'] if c['step']==0 else 'none'}
        context=json.loads(req['input'][0]['content']);assert context['question']==plan['question'] and context['branch']==task['branches'][c['turn']]
        assert context['task']=={k:task[k] for k in ['edges','items','bonuses']}
        if row['arm']=='baseline':assert 'nativeEvidence' not in context and c['suppliedAtoms']==[]
        else:
            from ascent_engine.evidence import expand_observation
            packet=expand_observation(context['nativeEvidence']);assert packet==c['entryEvidence']
            expected=list(dict.fromkeys(tuple(['path',*p]) for x in task['items'] for p in x['paths']))
            assert [tuple(o['conclusion']['atom']) for o in packet['observations']]==expected
            assert c['suppliedAtoms']==[o['conclusion']['atom'] for o in packet['observations'] if o['conclusion']['status']=='verified']
            for o in packet['observations']:
                f=o['conclusion'];assert (f['status']=='verified')==shared_truth(task,f['atom'])
                assert ('support' in o)==(row['arm']=='scheme' and f['status']=='verified')
        text=(folder/'thinking.txt').read_text();assert hashlib.sha256(text.encode()).hexdigest()==c['thinkingSha256'];visible+=len(text)
        if c['step']==0:assert len(req['input'])==1
        else:assert req['input']==previous[c['turn']]
        if c['grossTokens'] is not None:
            u=c['usage'];assert c['grossTokens']==u['input_tokens']+u['output_tokens'];gross+=c['grossTokens']
            assert c['atGrossTokens']==gross and u['input_tokens']<=c['inputReservation'] and u['output_tokens']<=c['outputCap']
            assert gross-c['grossTokens']+c['outputCap']+c['inputReservation']<=plan['totalBudget']
        if c.get('outputTruncated'):
            assert row['failure'] and not any(x['turn']==c['turn'] and x['step']>0 for x in row['calls']), 'incomplete thinking was salvaged'
        if c.get('submissionContinuation'):
            assert c['step']==0
            if c.get('outputTruncated'):assert terminal['status']=='incomplete'
            projected=branch_submission_context(terminal)
            assert projected[0]['content'][0]['text'].startswith(text)
            previous[c['turn']]=req['input']+projected
        opaque.append({'turn':c['turn'],'step':c['step'],'visibleThinkingCharacters':len(text),'status':c.get('status'),'outputTruncated':c.get('outputTruncated',False),'inputTokens':(c.get('usage') or {}).get('input_tokens'),'thinkingTokens':((c.get('usage') or {}).get('output_tokens_details') or {}).get('reasoning_tokens')})
    for b in row['branches']:assert b['grade']==branch_grade(task,task['branches'][b['turn']],b['selected'])
    assert row['grossTokens']==gross<=plan['totalBudget']
    outcomes.append({'case':row['case'],'arm':row['arm'],'grossTokens':gross,'submittedBranches':len(row['branches']),'stop':row['stop'],'failure':row['failure'],'visibleThinkingCharacters':visible,'calls':opaque})
assert sum(len(r['calls']) for r in rows)<=plan['maxTotalSolverCalls']
result={'passed':True,'planSha256':hashlib.sha256((frozen/'plan.json').read_bytes()).hexdigest(),'producerHead':plan['sourceState']['head'],'checks':'Native entry packet prior to first thinking, no extra instructions, exact assistant thinking projection, costs/reservations/ceiling, objective scores vs independent frozen grader','outcomes':outcomes}
(run/'audit.json').write_text(json.dumps(result,indent=2)+'\n');print('BRANCH_ENTRY_RUN_AUDIT_OK',[(r['case'],r['arm'],r['grossTokens'],r['submittedBranches'],r['failure']) for r in outcomes])
