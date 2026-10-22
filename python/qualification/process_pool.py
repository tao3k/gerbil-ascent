"""Installed Scheme-profile wheel: real calls through twelve resident VMs."""
from concurrent.futures import ThreadPoolExecutor
import gc
import os
from pathlib import Path

from ascent import Atom, Engine, ProcessPool, Program, Term


def qualify_rayon_modes():
    for distribution in ("adaptive", "across-requests", "within-request"):
        program = Program()
        program.relation("edge", ["integer", "integer"], source=True)
        program.relation("reach", ["integer", "integer"])
        x, y, z = [Term.var(i) for i in range(3)]
        program.rule(Atom("reach", [x, y]), [Atom("edge", [x, y])])
        program.rule(Atom("reach", [x, z]),
                     [Atom("reach", [x, y]), Atom("edge", [y, z])])
        engine = Engine(workers=12, backend="rayon", work_distribution=distribution)
        try:
            assert engine.work_distribution == distribution
            session = engine.open(program)
            session.replace("edge", [[1, 2], [2, 3]])
            first = session.run()
            assert first.rows("reach") == [[1, 2], [1, 3], [2, 3]]
            session.replace("edge", [[4, 5]])
            try:
                session.run(max_states=0)
            except RuntimeError:
                pass
            else:
                raise AssertionError("resource failure was ignored")
            assert session.last_completed().rows("reach") == first.rows("reach")
            session.replace("edge", [[4, 5]])
            assert session.run().rows("reach") == [[4, 5]]
        finally:
            engine.shutdown()
    try:
        Engine(workers=12, work_distribution="unknown")
    except ValueError:
        pass
    else:
        raise AssertionError("unknown work distribution was accepted")
    print("RAYON-PYTHON-OK threads=12 modes=3 limits=preserved snapshots=preserved", flush=True)


def qualify():
    pool = ProcessPool(12)
    identities = pool.identities()
    assert len(identities) == 12
    assert len({row['pid'] for row in identities}) == 12
    assert all(row['processors'] == 1 for row in identities)
    if worker := os.environ.get('ASCENT_SCHEME_WORKER'):
        for row in identities:
            executable = Path(f"/proc/{row['pid']}/exe")
            if executable.exists():
                assert executable.samefile(worker), 'explicit Rust worker was ignored'
    engines = [pool.engine(i, backend='scheme', max_source_scopes=8,
                           max_input_bytes=16384) for i in range(12)]
    assert all(engine.max_source_scopes == 8 for engine in engines)
    assert all(engine.max_input_bytes == 16384 for engine in engines)
    assert [engine.process_identity() for engine in engines] == identities
    modules = [engine.dsl(
        f'(def marker {i}) (def (answer x) (+ marker x)) '
        '(def (adder) (lambda (x) (+ marker x)))', trusted=True)
        for i, engine in enumerate(engines)]

    def call(index):
        owner = index % 12
        value = modules[owner].call('answer', index)
        assert int(value.graph['root']['value']) == owner + index
        value.close()
        closure = modules[owner].call('adder')
        answer = closure.apply(index)
        assert int(answer.graph['root']['value']) == owner + index
        answer.close()
        closure.close()

    with ThreadPoolExecutor(max_workers=12) as executor:
        list(executor.map(call, range(120)))
    for module in modules:
        module.close()
    for engine in engines:
        engine.shutdown()
    # Release all scope leases before retiring their common owner population.
    del module, engine, modules, engines
    return [row['pid'] for row in identities]


if __name__ == '__main__':
    qualify_rayon_modes()
    pids = qualify()
    gc.collect()
    for pid in pids:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            continue
        raise AssertionError(f'owned worker not reaped: {pid}')
    entry = 'selected-rust-worker' if os.environ.get('ASCENT_SCHEME_WORKER') else 'default-pyo3-worker'
    print(f'PROCESS-PYTHON-OK entry={entry} owners=12 processors=1 clients=12 calls=120 applications=120 reaped=12')
