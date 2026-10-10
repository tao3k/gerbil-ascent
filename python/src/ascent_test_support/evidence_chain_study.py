# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Independent three-arm study isolating retained component reuse from execution."""
import argparse,concurrent.futures,contextlib,copy,hashlib,json,multiprocessing,shutil,time
from pathlib import Path
from ascent_engine import Engine
from ascent_engine.conversation import ResponseHistory
from ascent_engine.derivations import EvidenceChain,normalize_contract
from . import evidence_chain_workload as workload
from . import inference_reuse_study as s
from .inference_effort import until_verified,paired_reduction
from .model_study import provider,response_outcome
from .movie_study import provider_key

ARMS=('raw-fact-reasoning','scheme-fresh-execution','scheme-retained-chain')
_ENGINE=None


def loose_json(text):
    """One JSON payload may be surrounded by prose or a Markdown fence."""
    if isinstance(text,(dict,list)):return copy.deepcopy(text)
    try:return json.loads(text)
    except (ValueError,TypeError):pass
    decoder=json.JSONDecoder();values=[];position=0
    while position<len(text):
        if text[position] not in '{[':position+=1;continue
        try:value,size=decoder.raw_decode(text[position:]);values.append(value);position+=size
        except ValueError:position+=1
    if len(values)!=1:raise ValueError('Provide one unambiguous JSON payload; surrounding prose is allowed.')
    return values[0]


def tools(assisted):
    definitions=[{'type':'function','name':'scan_facts','description':'Read named finite source relations; omit relations to read all. Actor indices refer to the ordered Actor domain returned here.',
                  'parameters':{'type':'object','properties':{'relations':{'type':'array','items':{'type':'string'}}}}},
                 {'type':'function','name':'submit_answer','description':'Submit actor identifiers or zero-based Actor indices, OR reference a previously checked unary result using reference and relation. Verification returns verified/not_verified. Sources are checked for identifier membership before grading.',
                  'parameters':{'type':'object','properties':{'answer':{'type':'array'},'reference':{'type':'string'},'relation':{'type':'string'}}}}]
    if assisted:definitions.append({'type':'function','name':'check_evidence',
        'description':'Execute expressed relational claims in Scheme. contract has relations (name/types) and rules (head/body atoms with relation/terms). Terms are var or const objects; body atoms may have not:true. A single head object or head array is accepted. Declare only new derived relations; answer already exists. queries selects relation names. Completed components may be reused according to returned retention metadata; re-express a previous definition or extend a retained claim. A check certifies rule consequences, not English intent.',
        'parameters':{'type':'object','properties':{'contract':{'type':'object'},'queries':{'type':'array','items':{'type':'string'}}}}})
    return definitions


def prepare(library,directory):
    directory.mkdir(parents=True,exist_ok=False);shutil.copy2(library,directory/library.name)
    paths=[Path(__file__),Path(workload.__file__),Path(s.__file__),
           Path(__file__).with_name('model_study.py'),Path(__file__).with_name('inference_effort.py'),Path(__file__).with_name('movie_study.py'),
           s.ROOT/'python/src/ascent_engine/__init__.py',s.ROOT/'python/src/ascent_engine/derivations.py',
           s.ROOT/'python/src/ascent_engine/evidence.py',s.ROOT/'python/src/ascent_engine/conversation.py']
    plan={'schema':'ascent.evidence-chain-study.v1','corpusKind':'synthetic-mechanism-regression','arms':list(ARMS),'repetitions':2,'maxTurns':8,'maxOutputTokens':131072,'workers':2,
          'library':library.name,'librarySha256':hashlib.sha256(library.read_bytes()).hexdigest(),
          'cases':[workload.workload(i,20271011+i*1009) for i in range(4)],
          'producerHashes':{str(p.relative_to(s.ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},
          'primary':'Cumulative thinking through first independently verified correct answer; all failures and repairs charged, censoring retained.',
          'ablation':'Fresh and retained Scheme arms have identical tools, instructions, result references and provider reasoning history; only component persistence differs.',
          'holdout':'New compound structures, 120 entities, new random chords and seeds; no original question/source reused. Frozen before paid calls.',
          'outputPolicy':'Automatic tool choice, no response-format schema, no required tool choice, prose-wrapped JSON accepted, equivalent singleton head normalized locally; Scheme authority/type/stratification validation preserved.',
          'recovery':'Output exhaustion stays charged and full incomplete reasoning is forwarded within the eight-turn bound. No gold feedback.',
          'costBoundary':'Result references available identically in both Scheme arms; this optimization cannot be credited to retained component reuse.'}
    (directory/'plan.json').write_text(json.dumps(plan,indent=2)+'\n')


def grade_answer(args,chain,case,observed):
    if not observed:raise ValueError('Acquire source facts or checked evidence before submitting an answer.')
    if 'reference' in args:
        values=[r[0] for r in chain.answer(args['reference'],args.get('relation','answer'))]
    else:
        values=args['answer']
        if not isinstance(values,list):raise ValueError('answer must be a list or a checked result reference')
        domain=case['source']['domains']['Actor']
        values=[domain[x] if type(x)==int and 0<=x<len(domain) else x for x in values]
        if any(not isinstance(x,str) or x not in domain for x in values):raise ValueError('Answer contains identifiers outside the supplied Actor domain; original identifiers or zero-based domain indices are accepted.')
    return sorted(set(values))==[r[0] for r in workload.expected(case,case['source'])]


def episode(plan,plan_dir,output,case,rep,arm):
    global _ENGINE
    directory=output/f"{case['name']}-rep-{rep}-{arm}";directory.mkdir();(directory/'paid-claim.json').open('x').close()
    with (directory/'progress.txt').open('w') as log,contextlib.redirect_stdout(log):
        if _ENGINE is None:_ENGINE=Engine(plan_dir/plan['library'])
        assisted=arm!=ARMS[0];base=s.program(case['source'],{'relations':[],'rules':[]})
        record={'case':case['name'],'repetition':rep,'arm':arm,'attempts':[],'evidenceJournal':[]}
        def save():(directory/'episode.json').write_text(json.dumps(record,indent=2)+'\n')
        history=ResponseHistory(json.dumps({'question':case['question'],'schema':s.SCHEMA},sort_keys=True));origins={};observed=False
        instructions=('Solve the complete complex question using only supplied finite relations. Reason naturally; no subproblem-first plan is required. '
                      'cast maps Film to Actor; directed Film to Director; citizen Director to Country; mentor is directed Actor to Actor. '
                      'Positive recursion uses a least fixed point; negation must be stratified and positively bound. Source heads are forbidden. '
                      'Function calls are available but not forced. Prose and fenced JSON are accepted for a final answer. '
                      'An answer can use original actor IDs or zero-based Actor indices, so copying opaque strings is unnecessary. '
                      'For Scheme tools, a checked unary relation can be submitted by result reference; this does not certify English intent. '
                      'Use existing checked components when the retention metadata permits; avoid reconstructing a completed recursive closure. '
                      'Do not redeclare source relations or the already declared answer(Actor). A single head atom or head array is accepted. '
                      'If needed, extend expressed claims in a later check. Verification reveals no correct values. '
                      +('Scheme execution is available.' if assisted else 'Reason over scanned raw facts; Scheme execution is unavailable.'))
        started=time.monotonic()
        with EvidenceChain(_ENGINE,[r for r in base['relations'] if r['source']],arm==ARMS[2]) as chain:
            record['setupSeconds']=time.monotonic()-started;save();key=provider_key()
            for turn in range(1,plan['maxTurns']+1):
                request={'model':'deepseek-flash','input':history.input(),'instructions':instructions,'tools':tools(assisted),
                         'tool_choice':'auto','reasoning':{'effort':'high'},'max_output_tokens':plan['maxOutputTokens'],'stream':True,'store':False}
                (directory/f'{turn}.request.json').write_text(json.dumps(request,indent=2)+'\n')
                raw,meta=provider(request,key,directory/f'{turn}.response.json');(directory/f'{turn}.raw.txt').write_text(raw)
                terminal=meta.get('terminal')or{};outcome=response_outcome(meta)
                a={'turn':turn,'providerCalls':1,'usage':terminal.get('usage'),'correct':False,'providerOutcome':outcome,
                   'providerSeconds':meta['providerSeconds'],'priorReasoningItems':history.reasoning_items,'toolActions':[],
                   'requestSha256':s.identity(request),'sourceIdentity':chain.source_identity}
                record['attempts'].append(a);save()
                if meta.get('error') or not a['usage']:a['outcome']='provider_failure';save();raise RuntimeError('Transport failed; stop dispatch, retain partial receipt.')
                calls=history.append_response(terminal);started=time.monotonic()
                if not calls:
                    try:
                        value=loose_json(raw);args=value if isinstance(value,dict) else {'answer':value}
                        a['correct']=grade_answer(args,chain,case,observed);a['action']={'action':'answer',**args}
                        feedback={'verification':'verified' if a['correct'] else 'not_verified'}
                        a['outcome']='verified_answer' if a['correct'] else 'answer_not_verified'
                    except Exception as error:
                        feedback={'error':str(error)[:2048],'guidance':'You may use submit_answer, actor indices, or one prose-wrapped JSON answer payload.'}
                        a['outcome']='output_budget_exhausted' if outcome=='output_budget_exhausted' else 'action_failure'
                    a['feedback']=feedback;history.append_feedback(feedback)
                for call in calls:
                    action={'name':call['name'],'callId':call['call_id'],'correct':False};a['toolActions'].append(action)
                    try:
                        if call.get('status')=='incomplete':raise ValueError('Incomplete function call was not executed; continue with a complete call.')
                        args=loose_json(call['arguments'])
                        if call['name']=='scan_facts':
                            names=args.get('relations',list(s.SCHEMA));feedback=chain.scan(names);feedback['actorIndices']=case['source']['domains']['Actor'];observed=True;kind='scan'
                        elif call['name']=='check_evidence' and assisted:
                            contract=normalize_contract(args['contract']);program=s.program(case['source'],contract);program['queries']=args.get('queries',['answer'])
                            feedback=chain.query(program);observed=True;kind='query'
                            for component in feedback['freshComponents']:origins.setdefault(component['fingerprint'],turn)
                            feedback['crossRoundReusedComponents']=[c for c in feedback['reusedComponents'] if origins.get(c['fingerprint'],turn)<turn]
                            record['evidenceJournal'].append(feedback)
                        elif call['name']=='submit_answer':
                            kind='answer';action['correct']=grade_answer(args,chain,case,observed);a['correct']|=action['correct']
                            feedback={'verification':'verified' if action['correct'] else 'not_verified'}
                        else:raise ValueError('Tool unavailable in this condition.')
                        action.update(action={'action':kind,**args},outcome='verified_answer' if action['correct'] else 'answer_not_verified' if kind=='answer' else 'evidence_progress')
                    except Exception as error:
                        feedback={'error':str(error)[:2048]};action['outcome']='action_failure'
                    action['feedback']=feedback;history.append_result(call['call_id'],feedback)
                if calls:a['outcome']='verified_answer' if a['correct'] else 'output_budget_exhausted' if outcome=='output_budget_exhausted' else 'action_failure' if any(t['outcome']=='action_failure' for t in a['toolActions']) else 'answer_not_verified' if any(t['outcome']=='answer_not_verified' for t in a['toolActions']) else 'evidence_progress'
                a['schemeSeconds']=time.monotonic()-started;record['effort']=until_verified(record['attempts']);save()
                print('CHAIN-ROUND',case['name'],rep,arm,turn,a['outcome'],flush=True)
                if a['correct']:break
            record['effort']=until_verified(record['attempts']);save()
    return record


def live(plan_dir,output):
    pp=plan_dir/'plan.json';plan=json.loads(pp.read_text())
    if plan.get('corpusKind')!='admitted-external-source':
        raise ValueError('Paid primary evaluation requires admitted external-source tasks; synthetic cases are offline mechanism regressions.')
    for rel,sha in plan['producerHashes'].items():
        if hashlib.sha256((s.ROOT/rel).read_bytes()).hexdigest()!=sha:raise ValueError('producer drift')
    if hashlib.sha256((plan_dir/plan['library']).read_bytes()).hexdigest()!=plan['librarySha256']:raise ValueError('library drift')
    output.mkdir(parents=True,exist_ok=False);(plan_dir/'paid-claim.json').open('x').close()
    receipt={'schema':'ascent.evidence-chain-result.v1','planSha256':hashlib.sha256(pp.read_bytes()).hexdigest(),'providerCalls':0,'peakEstimateUsd':0,'episodes':[]}
    def save():(output/'result.json').write_text(json.dumps(receipt,indent=2)+'\n')
    def add(e):
        receipt['episodes'].append(e);receipt['providerCalls']+=len(e['attempts']);receipt['peakEstimateUsd']+=sum(s.price(a['usage']) for a in e['attempts']);save()
    save();jobs=[]
    for i,case in enumerate(plan['cases']):
        for rep in range(plan['repetitions']):
            order=list(ARMS);offset=(i+rep)%3;order=order[offset:]+order[:offset]
            jobs.extend((case,rep,arm) for arm in order)
    # One real trajectory qualifies transport before any concurrent fan-out.
    add(episode(plan,plan_dir,output,*jobs.pop(0)))
    with concurrent.futures.ProcessPoolExecutor(max_workers=2,mp_context=multiprocessing.get_context('spawn')) as pool:
        iterator=iter(jobs);pending={pool.submit(episode,plan,plan_dir,output,*next(iterator)) for _ in range(2)}
        while pending:
            done,pending=concurrent.futures.wait(pending,return_when=concurrent.futures.FIRST_COMPLETED)
            for future in done:
                try:add(future.result())
                except Exception:
                    for other in pending:other.cancel()
                    raise
                job=next(iterator,None)
                if job:pending.add(pool.submit(episode,plan,plan_dir,output,*job))
    receipt['complete']=True;save();print('EVIDENCE-CHAIN-COMPLETE',receipt['providerCalls'],flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['prepare','live']);p.add_argument('source',type=Path);p.add_argument('output',type=Path)
    a=p.parse_args();prepare(a.source,a.output) if a.mode=='prepare' else live(a.source,a.output)
