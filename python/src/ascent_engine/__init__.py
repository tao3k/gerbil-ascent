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
import errno
import tempfile
from dataclasses import dataclass
from cffi import FFI
from .artifact import ArtifactValidation


@dataclass(frozen=True)
class FactLimits:
    """Optional caller ceilings. None means no ceiling, not a large integer.

    Scheme validates/enforces occurrence counts. Explicit DSL bounds can only
    be tightened; this transport object never counts or admits facts itself.
    """
    input: int | None = None
    derived: int | None = None
    output: int | None = None

    def wire(self):
        return {key: value for key, value in vars(self).items() if value is not None}


def _with_limits(request, limits):
    if limits is not None:
        request['factLimits'] = limits.wire()
    return request

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
_runtime_initialized = False
_runtime_closed = False
_configured_syntax = None
_artifact_validation = ArtifactValidation()

def _host_descriptor_names():
    """Retry transient Darwin descriptor-directory reads before native entry."""
    for attempt in range(3):
        try:
            return os.listdir('/dev/fd')
        except OSError as error:
            if error.errno not in (errno.EINTR, errno.EAGAIN) or attempt == 2:
                raise

@contextlib.contextmanager
def _preserve_host_io():
    """Keep Gambit flag changes off inherited host open-file descriptions."""
    descriptors = {}
    for name in _host_descriptor_names():
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
    def __init__(self, library=None, *, max_request_bytes=None, max_source_scopes=None):
        global _loaded, _runtime_pid, _runtime_initialized, _configured_syntax
        if max_request_bytes is not None and (type(max_request_bytes) is not int or max_request_bytes <= 0):
            raise ValueError('max_request_bytes must be a positive integer or None')
        self.max_request_bytes = max_request_bytes
        if max_source_scopes is not None and (type(max_source_scopes) is not int or max_source_scopes <= 0):
            raise ValueError('max_source_scopes must be a positive integer or None')
        self.max_source_scopes = max_source_scopes
        if _runtime_pid is not None and os.getpid() != _runtime_pid:
            raise EngineError(-2, 'inherited runtime after fork; start a fresh process')
        if _runtime_closed:
            raise EngineError(-2, 'runtime shut down')
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
        receipt_path = Path(path).parent / 'receipt.json' if library is None else Path(path + '.json')
        receipt = None
        if receipt_path.is_file() or _artifact_validation.has_receipt(receipt_path):
            try:
                receipt = _artifact_validation.read(path, receipt_path)
            except (ValueError, OSError) as error:
                raise EngineError(-2, str(error)) from error
        if library is not None and _loaded is None:
            ffi = FFI(); ffi.cdef(CDEF); lib = ffi.dlopen(path)
        if _loaded is None:
            _loaded = (path, ffi, lib, self.backend)  # Keep mapped for the runtime lifetime.
            _runtime_pid = os.getpid()
        elif _loaded[0] != path:
            raise EngineError(-2, 'one engine library per Python process')
        _, self.ffi, self.lib, _ = _loaded
        if self.lib.ascent_abi_version() != 1: raise EngineError(-2, 'ABI mismatch')
        if not _runtime_initialized:
            child_handler = signal.getsignal(signal.SIGCHLD)
            with _preserve_host_io():
                status = self.lib.ascent_runtime_init()
            # The embedding host owns subprocess reaping.
            if child_handler is not None:
                signal.signal(signal.SIGCHLD, child_handler)
            if status: raise EngineError(status, 'runtime initialization')
            _runtime_initialized = True
        self.owner = threading.get_ident(); self.closed = False
        self.build_receipt = receipt
        if receipt and receipt.get('syntaxResources'):
            syntax = str(receipt_path.parent / 'syntax')
            if _configured_syntax is not None and _configured_syntax != syntax:
                raise EngineError(-2, 'native syntax resources cannot change in a loaded runtime')
            if _configured_syntax is None:
                self._dispatch({'operation': 'configure-syntax', 'path': syntax}, None)
                _configured_syntax = syntax

    def request(self, request):
        return self._dispatch(request, self.max_request_bytes)

    def _dispatch(self, request, max_request_bytes):
        if os.getpid() != _runtime_pid:
            raise EngineError(-2, 'inherited runtime after fork')
        if self.closed: raise EngineError(-2, 'runtime shut down')
        if threading.get_ident() != self.owner: raise EngineError(-3, 'wrong OS thread')
        if self.max_source_scopes is not None and request.get('operation') in (
                'dsl-open', 'open-evidence', 'components-open', 'open-components'):
            request = dict(request)
            ceiling = request.get('maxSourceScopes', self.max_source_scopes)
            if type(ceiling) is not int or ceiling <= 0:
                raise ValueError('maxSourceScopes must be a positive integer')
            request['maxSourceScopes'] = min(ceiling, self.max_source_scopes)
        data = json.dumps(request, ensure_ascii=False, allow_nan=False).encode()
        if not data or (max_request_bytes is not None and len(data) > max_request_bytes):
            raise EngineError(-4, 'caller input byte bound')
        result = self.ffi.new('ascent_result *')
        with _preserve_host_io():
            try:
                status = self.lib.ascent_request(data, len(data), result)
                payload = bytes(self.ffi.buffer(result.payload, result.length)) if result.payload else b''
                if status: raise EngineError(status, payload.decode(errors='replace'))
                return json.loads(payload)
            finally:
                self.lib.ascent_result_release(result)

    def open(self, program, *, limits=None):
        return Session(self, self.request(_with_limits({'operation': 'open', 'program': program}, limits))['handle'])

    def read_rules(self, *sources):
        """Read inert native ASCENT text in the installed engine, never a compiler."""
        return self.request({'operation': 'read-rules', 'sources': list(sources)})

    def open_sources(self, *sources, limits=None):
        """Load pure DSL text through the existing upstream native lowering."""
        return SourceSession(self, self.request(_with_limits({'operation': 'open-sources', 'sources': list(sources)}, limits)))

    def open_rule_sources(self, *sources, limits=None):
        """Open inert typed ASCENT rules; executable Scheme forms are rejected."""
        return SourceSession(self, self.request(_with_limits(
            {'operation': 'open-rule-sources', 'sources': list(sources)}, limits)))

    def open_module(self, module, constructor, *arguments, limits=None):
        """Invoke a trusted compiled Scheme module's exported constructor."""
        return SourceSession(self, self.request(_with_limits({'operation': 'open-module', 'module': module,
                                                'constructor': constructor, 'arguments': list(arguments)}, limits)))

    def module(self, module):
        """Own arbitrary values from trusted, compiled native module exports."""
        return Module(self, self.request({'operation': 'module-open', 'module': module})['owner'])

    def dsl(self, source, *, trusted=False):
        """Own values from scenario DSL definitions in the native Library.

        Consumers need Python, not gxc or gerbil.pkg. This is not a sandbox.
        The Library owns imports and scope. Native execution can have host effects.
        """
        if trusted is not True:
            raise ValueError('trusted host Scheme execution must be explicitly authorized')
        return Module(self, self.request({'operation': 'dsl-open',
                            'source': source, 'trusted': True})['owner'])

    def evidence(self, source, constructor, *arguments, trusted=False, limits=None):
        """Open a native session from scenario DSL, without Scheme scaffolding."""
        if trusted is not True:
            raise ValueError('trusted host Scheme execution must be explicitly authorized')
        return SourceSession(self, self.request(_with_limits({'operation': 'open-evidence',
                            'source': source, 'trusted': True,
                            'constructor': constructor, 'arguments': list(arguments)}, limits)))

    def components(self, manifest, sources, entry, *, trusted=False):
        """Load a native dependency closure of independently scoped definitions.

        Sources map manifest paths to exact text. Scheme owns validation,
        dependency selection and linking; this method only transports them.
        """
        if trusted is not True:
            raise ValueError('trusted host Scheme execution must be explicitly authorized')
        receipt = self.request({'operation': 'components-open', 'components': manifest,
                                'sources': sources, 'entry': entry, 'trusted': True})
        owner = Module(self, receipt['owner'])
        owner.components = tuple(receipt['components'])
        return owner

    def evidence_components(self, manifest, sources, entry, constructor, *arguments,
                            trusted=False, limits=None):
        """Open an upstream session from a native component constructor."""
        if trusted is not True:
            raise ValueError('trusted host Scheme execution must be explicitly authorized')
        return SourceSession(self, self.request(_with_limits({
            'operation': 'open-components', 'components': manifest, 'sources': sources,
            'entry': entry, 'constructor': constructor, 'arguments': list(arguments),
            'trusted': True}, limits)))

    def shutdown(self):
        global _runtime_closed
        if os.getpid() != _runtime_pid:
            raise EngineError(-2, 'inherited runtime after fork')
        if self.closed: return
        with _preserve_host_io():
            status = self.lib.ascent_runtime_shutdown()
        if status: raise EngineError(status, 'runtime shutdown')
        _runtime_closed = True
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


class SourceSession(Session):
    def __init__(self, engine, receipt):
        super().__init__(engine, receipt['handle'])
        self.descriptors = receipt['descriptors']
        self.projection = receipt['projection']
        self.fact_limits = receipt['factLimits']
        self.queries = tuple(receipt['queries'])

    def _check(self):
        if self.handle is None:
            raise ValueError('native DSL session closed')

    def replace(self, sources):
        self._check()
        if isinstance(sources, dict):
            sources = [{'relation': name, 'rows': rows} for name, rows in sources.items()]
        return self.engine.request({'operation': 'source-replace', 'handle': self.handle, 'sources': sources})

    def run(self, timeout_nanoseconds=1000000000, *, queries=None):
        self._check()
        return self.engine.request({'operation': 'source-run', 'handle': self.handle,
                                   'queries': list(self.queries if queries is None else queries),
                                   'timeoutNanoseconds': timeout_nanoseconds})

    def result(self, receipt):
        self._check()
        return Result(self, receipt['resultHandle'])

    def close(self):
        if self.handle is not None:
            super().close()
            self.handle = None


class Result:
    """Owned native value; encoding and explanation do not rerun inference."""
    def __init__(self, session, handle):
        self.session, self.handle = session, handle

    def _request(self, action, **fields):
        self.session._check()
        if self.handle is None:
            raise ValueError('native result released')
        return self.session.engine.request({'operation': 'native-result',
                                           'handle': self.session.handle, 'result': self.handle,
                                           'action': action, **fields})

    def rows(self, relation):
        return self._request('rows', relation=relation)

    def explain(self, relation):
        return self._request('explain', relation=relation)

    def explanation(self, relation):
        """Own an explanation separately from the result that produced it."""
        return Explanation(self.session, self.explain(relation))

    def close(self):
        if self.handle is not None:
            if self.session.handle is not None and not self.session.engine.closed:
                self._request('release')
            self.handle = None

    def __enter__(self): return self
    def __exit__(self, *exc): self.close()


class Explanation:
    def __init__(self, session, receipt):
        self.session, self.receipt = session, receipt
        self.handle = receipt['explanationHandle']

    @property
    def graph(self):
        self.session._check()
        if self.handle is None:
            raise ValueError('native explanation released')
        return self.receipt['value']

    def reference(self, node):
        self.session._check()
        if self.handle is None:
            raise ValueError('native explanation released')
        return {'type': 'reference', 'result': self.handle, 'node': node}

    def close(self):
        if self.handle is not None:
            if self.session.handle is not None and not self.session.engine.closed:
                self.session.engine.request({'operation': 'native-result', 'handle': self.session.handle,
                                             'result': self.handle, 'action': 'release'})
            self.handle = None

    def __enter__(self): return self
    def __exit__(self, *exc): self.close()


class Module:
    """ABI ownership only; exported Scheme procedures own all semantics."""
    def __init__(self, engine, handle):
        self.engine, self.handle = engine, handle

    def _request(self, operation, **fields):
        if self.handle is None:
            raise ValueError('native module owner closed')
        return self.engine.request({'operation': operation, 'owner': self.handle, **fields})

    def call(self, export, *arguments, module=None, component=None):
        fields = {} if module is None else {'module': module}
        if component is not None:
            fields['component'] = component
        return Value(self, self._request('module-call', export=export, arguments=list(arguments), **fields))

    def evidence(self, constructor, *arguments, component=None, limits=None):
        """Construct an independent session from already loaded definitions.

        Native Scheme owns constructor execution and policy validation. The
        session retains its Program and explanation independently of this owner.
        """
        fields = {} if component is None else {'component': component}
        if limits is not None:
            fields['factLimits'] = limits.wire()
        return SourceSession(self.engine, self._request('owner-evidence',
                              constructor=constructor, arguments=list(arguments), **fields))

    def close(self):
        if self.handle is not None:
            if not self.engine.closed:
                self._request('module-close')
            self.handle = None

    def __enter__(self): return self
    def __exit__(self, *exc): self.close()


class Value:
    """Actual native return value, independently of graph projection."""
    def __init__(self, module, receipt):
        self.module, self.receipt = module, receipt
        self.handle = receipt['valueHandle']

    @property
    def graph(self):
        if self.handle is None or self.module.handle is None:
            raise ValueError('native value released')
        return self.receipt.get('value')

    def reference(self, node=None):
        if self.handle is None:
            raise ValueError('native value released')
        if node is None:
            return self.module._request('module-value', value=self.handle, action='reference')
        if self.module.handle is None:
            raise ValueError('native module owner closed')
        return {'type': 'reference', 'result': self.handle, 'node': node}

    def apply(self, *arguments):
        if self.handle is None:
            raise ValueError('native value released')
        return Value(self.module, self.module._request('module-apply', value=self.handle,
                                                            arguments=list(arguments)))

    def close(self):
        if self.handle is not None:
            if self.module.handle is not None and not self.module.engine.closed:
                self.module._request('module-value', value=self.handle, action='release')
            self.handle = None

    def __enter__(self): return self
    def __exit__(self, *exc): self.close()
