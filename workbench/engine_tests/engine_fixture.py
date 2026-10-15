"""Installed Rust engine plus explicitly registered Scheme qualification fixtures."""
from pathlib import Path
from ascent import Engine

ROOT = Path(__file__).resolve().parents[2]


def module_engine():
    engine = Engine()
    source = ROOT / 't/qualification/evidence-api-module.ss'
    engine.register_module(':gerbil-ascent/t/qualification/evidence-api-module',
                           source.read_text(), trusted=True)
    return engine


def finite_movie_program(engine, family):
    """The same finite movie rule families, parsed by the original Scheme reader."""
    exclusion = '(not (blocked_actor A))'
    left = exclusion
    right = exclusion if family == 1 else ''
    answer = ('((actor_answer A) <-- (left_evidence F A) (right_evidence G A))'
              if family == 2 else
              '((actor_answer A) <-- (left_evidence F A)) ((actor_answer A) <-- (right_evidence F A))')
    source = f'''(ascent-fragment
      (relation cast ((f symbol?) (a symbol?)))
      (relation left_film ((f symbol?))) (relation right_film ((f symbol?)))
      (relation blocked_actor ((a symbol?)))
      (relation left_evidence ((f symbol?) (a symbol?)))
      (relation right_evidence ((f symbol?) (a symbol?)))
      (relation actor_answer ((a symbol?)))
      (relation cast_trace ((scope symbol?) (f symbol?) (a symbol?)))
      ((left_evidence F A) <-- (left_film F) (cast F A) {left})
      ((right_evidence F A) <-- (right_film F) (cast F A) {right})
      {answer}
      ((cast_trace (lit 'left) F A) <-- (actor_answer A) (left_evidence F A))
      ((cast_trace (lit 'right) F A) <-- (actor_answer A) (right_evidence F A)))'''
    program = engine.read_rules(source)
    initial = {'cast': [[f, a] for f in ('movie-left', 'movie-right') for a in ('a0','a1','a2')],
               'left_film': [['movie-left']], 'right_film': [['movie-right']], 'blocked_actor': [['a0']]}
    for relation in program['relations']:
        name = relation['name']
        relation['rows'] = initial.get(name, [])
        if name == 'cast': domains = [['movie-left','movie-right'], ['a0','a1','a2']]
        elif name in ('left_film', 'right_film'): domains = [['movie-left','movie-right']]
        elif name == 'blocked_actor': domains = [['a0','a1','a2']]
        else: continue
        for column, domain in zip(relation['columns'], domains): column['domain'] = domain
    program['queries'] = ['actor_answer','cast_trace','left_evidence','right_evidence']
    return program
