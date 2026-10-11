"""Offline syntax-reference coverage audit; does not call a provider."""
import sys,json
from pathlib import Path
build=Path(sys.argv[1]).resolve();sys.path[:0]=[str(build/'source/python/src'),str(build/'frozen/api-runtime')]
from ascent_test_support.evidence_chain_study import branch_literal_episodes
reference=json.loads((Path(__file__).resolve().parent/'coverage-reference.json').read_text());total=matched=characters=0
for r in reference['responses'].values():
 result=branch_literal_episodes(r['text'],reference['tasks'][r['case']],[],[],r['turn'],r['step'])
 assert result['coveredCharacters']==len(r['text']);characters+=len(r['text'])
 for e in r['reviewed']:
  total+=1
  matched+=any(x['atom']==e['atom'] and e['span'][0]<=x['span'][0] and x['span'][1]<=e['span'][1] for x in result['episodes'])
assert total==matched==38
print('LITERAL_REFERENCE_REPLAY_OK',characters,matched,total)
