"""Installed Scheme-profile wheel: real calls through twelve resident VMs."""
from concurrent.futures import ThreadPoolExecutor
import gc
import os
from pathlib import Path

from ascent import ProcessPool


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
