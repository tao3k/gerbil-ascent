# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Python CFFI binding to the ASCENT finite declarative engine C ABI."""
import json
from pathlib import Path
import threading
import atexit
from cffi import FFI

CDEF = '''
typedef struct { int32_t status; uint8_t *payload; size_t length; } ascent_result;
uint32_t ascent_abi_version(void);
int32_t ascent_runtime_init(void);
int32_t ascent_runtime_shutdown(void);
int32_t ascent_request(const uint8_t *, size_t, ascent_result *);
void ascent_result_release(ascent_result *);
'''
_loaded = None

def _shutdown():
    if _loaded is not None: _loaded[2].ascent_runtime_shutdown()
atexit.register(_shutdown)

class EngineError(RuntimeError):
    def __init__(self, status, detail):
        self.status = status
        super().__init__(f'ASCENT engine status {status}: {detail}')

class Engine:
    """One process runtime, bound to its initializing OS thread.

    Close sessions individually; shutdown is explicit and terminal for the
    entire loaded runtime. Never dlclose a live Gambit runtime.
    """
    def __init__(self, library):
        global _loaded
        if threading.get_ident() != threading.main_thread().ident:
            raise EngineError(-3, 'Python binding initialization requires the main OS thread')
        path = str(Path(library).resolve())
        if _loaded is None:
            ffi = FFI(); ffi.cdef(CDEF); lib = ffi.dlopen(path)
            _loaded = (path, ffi, lib)  # Keep library mapped for the runtime lifetime.
        elif _loaded[0] != path:
            raise EngineError(-2, 'one engine library per Python process')
        _, self.ffi, self.lib = _loaded
        if self.lib.ascent_abi_version() != 1: raise EngineError(-2, 'ABI mismatch')
        status = self.lib.ascent_runtime_init()
        if status: raise EngineError(status, 'runtime initialization')
        self.owner = threading.get_ident(); self.closed = False

    def request(self, request):
        if self.closed: raise EngineError(-2, 'runtime shut down')
        if threading.get_ident() != self.owner: raise EngineError(-3, 'wrong OS thread')
        data = json.dumps(request, ensure_ascii=False, allow_nan=False).encode()
        if not 0 < len(data) <= 1048576: raise EngineError(-4, 'input byte bound')
        result = self.ffi.new('ascent_result *')
        try:
            status = self.lib.ascent_request(data, len(data), result)
            payload = bytes(self.ffi.buffer(result.payload, result.length)) if result.payload else b''
            if status: raise EngineError(status, payload.decode(errors='replace'))
            return json.loads(payload)
        finally:
            self.lib.ascent_result_release(result)

    def open(self, program):
        return Session(self, self.request({'operation': 'open', 'program': program})['handle'])

    def shutdown(self):
        if self.closed: return
        status = self.lib.ascent_runtime_shutdown()
        if status: raise EngineError(status, 'runtime shutdown')
        self.closed = True
    def __enter__(self): return self
    def __exit__(self, *exc): self.shutdown()

class Session:
    def __init__(self, engine, handle): self.engine, self.handle = engine, handle
    def run(self, timeout_nanoseconds=1000000000):
        return self.engine.request({'operation':'run', 'handle':self.handle,
                                   'timeoutNanoseconds':timeout_nanoseconds})
    def replace(self, sources):
        return self.engine.request({'operation':'replace', 'handle':self.handle, 'sources':sources})
    def close(self):
        self.engine.request({'operation':'close', 'handle':self.handle})
    def __enter__(self): return self
    def __exit__(self, *exc): self.close()
