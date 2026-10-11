# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Python CFFI binding to the ASCENT finite declarative engine C ABI."""
import json
from pathlib import Path
import threading
import atexit
import signal
import contextlib
import fcntl
import os
import tempfile
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
_runtime_pid = None

@contextlib.contextmanager
def _preserve_host_io():
    """Keep Gambit flag changes off inherited host open-file descriptions."""
    descriptors = {}
    for name in os.listdir('/dev/fd'):
        fd = int(name)
        try:
            stat = os.fstat(fd)
            descriptors[fd] = ((stat.st_dev, stat.st_ino, stat.st_mode), fcntl.fcntl(fd, fcntl.F_GETFL))
        except OSError:
            pass
    streams = []
    try:
        # dup alone shares status flags across spawned workers. During native
        # entry, standard ports use independently opened files instead. Retain
        # all native output and restore the caller's descriptors before replay.
        for fd in (0, 1, 2):
            if fd not in descriptors:
                continue
            inheritable = os.get_inheritable(fd)
            saved = os.dup(fd)
            try:
                stream = tempfile.TemporaryFile()
            except BaseException:
                os.close(saved)
                raise
            streams.append((fd, saved, stream, inheritable))
            os.dup2(stream.fileno(), fd, inheritable=inheritable)
        yield
    finally:
        for fd, saved, stream, inheritable in streams:
            os.dup2(saved, fd, inheritable=inheritable)
            os.close(saved)
        for fd, (identity, flags) in descriptors.items():
            if fd in (0, 1, 2):
                continue  # Native code never touched these original streams.
            try:
                stat = os.fstat(fd)
                if identity == (stat.st_dev, stat.st_ino, stat.st_mode):
                    if fcntl.fcntl(fd, fcntl.F_GETFL) != flags:
                        fcntl.fcntl(fd, fcntl.F_SETFL, flags)
            except OSError:
                pass
        for fd, saved, stream, inheritable in streams:
            try:
                if fd in (1, 2):
                    stream.seek(0)
                    while chunk := stream.read(65536):
                        remaining = memoryview(chunk)
                        while remaining:
                            remaining = remaining[os.write(fd, remaining):]
            finally:
                stream.close()

def _shutdown():
    if _loaded is not None and os.getpid() == _runtime_pid:
        with _preserve_host_io(): _loaded[2].ascent_runtime_shutdown()
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
    def __init__(self, library=None):
        global _loaded, _runtime_pid
        if _runtime_pid is not None and os.getpid() != _runtime_pid:
            raise EngineError(-2, 'inherited runtime after fork; start a fresh process')
        if threading.get_ident() != threading.main_thread().ident:
            raise EngineError(-3, 'Python binding initialization requires the main OS thread')
        self.backend = 'api' if library is None else 'abi'
        if _loaded is not None and _loaded[3] != self.backend:
            raise EngineError(-2, 'one binding backend per Python process')
        if library is None:
            # Compiled API mode: checked against ascent.h, never silently
            # fall back to loading another library when the extension is absent.
            import _ascent_cffi
            path = str(Path(_ascent_cffi.__file__).resolve())
            ffi, lib = _ascent_cffi.ffi, _ascent_cffi.lib
        else:
            path = str(Path(library).resolve())
            if _loaded is None:
                ffi = FFI(); ffi.cdef(CDEF); lib = ffi.dlopen(path)
        if _loaded is None:
            _loaded = (path, ffi, lib, self.backend)  # Keep mapped for the runtime lifetime.
            _runtime_pid = os.getpid()
        elif _loaded[0] != path:
            raise EngineError(-2, 'one engine library per Python process')
        _, self.ffi, self.lib, _ = _loaded
        if self.lib.ascent_abi_version() != 1: raise EngineError(-2, 'ABI mismatch')
        child_handler = signal.getsignal(signal.SIGCHLD)
        with _preserve_host_io():
            status = self.lib.ascent_runtime_init()
        # The embedding Python host owns subprocess reaping. Gambit's installed
        # SIGCHLD handler otherwise consumes statuses before Popen can collect
        # them, turning failed test commands into apparent zero exits.
        if child_handler is not None:
            signal.signal(signal.SIGCHLD, child_handler)
        if status: raise EngineError(status, 'runtime initialization')
        self.owner = threading.get_ident(); self.closed = False

    def request(self, request):
        if os.getpid() != _runtime_pid:
            raise EngineError(-2, 'inherited runtime after fork')
        if self.closed: raise EngineError(-2, 'runtime shut down')
        if threading.get_ident() != self.owner: raise EngineError(-3, 'wrong OS thread')
        data = json.dumps(request, ensure_ascii=False, allow_nan=False).encode()
        if not 0 < len(data) <= 1048576: raise EngineError(-4, 'input byte bound')
        result = self.ffi.new('ascent_result *')
        with _preserve_host_io():
            try:
                status = self.lib.ascent_request(data, len(data), result)
                payload = bytes(self.ffi.buffer(result.payload, result.length)) if result.payload else b''
                if status: raise EngineError(status, payload.decode(errors='replace'))
                return json.loads(payload)
            finally:
                self.lib.ascent_result_release(result)

    def open(self, program):
        return Session(self, self.request({'operation': 'open', 'program': program})['handle'])

    def read_rules(self, *sources):
        """Read inert native ASCENT text in the installed engine, never a compiler."""
        return self.request({'operation': 'read-rules', 'sources': list(sources)})

    def shutdown(self):
        if os.getpid() != _runtime_pid:
            raise EngineError(-2, 'inherited runtime after fork')
        if self.closed: return
        with _preserve_host_io():
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
