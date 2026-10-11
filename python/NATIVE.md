# Scheme AOT to Python

The supported design is:

```
Scheme semantic engine -> Gerbil/Gambit AOT -> libascent C ABI
                     -> compiled CFFI API extension -> Python objects
```

Python does not implement a second inference engine or run a Scheme subprocess
per request. Bulk finite relations cross the existing inert JSON boundary;
sessions retain Scheme state, and EvidenceChain reuses completed components.
This enlarges the usable Python surface, not the set of formally proven claims.

## Inert ASCENT Rule Sources

`Engine.read_rules(*sources)` passes raw Scheme text to the installed native
engine. Sources contain typed `(ascent-fragment ...)` declarations and native
`<--` rules, without imports. The engine uses an inert reader with reader
evaluation and shared/cyclic datums disabled, then native schema and program
admission. It does not evaluate Scheme code or invoke a compiler at request time.

The supported subset includes typed scalar relations, relational multi-head
rules, stratified negation and closed checked `<`/`even?` clauses. Arbitrary
callbacks, imports, aggregates and wildcards are rejected. Each source is bounded
to 64 KiB, with at most 16 sources and 256 KiB total. JSON remains the existing
C ABI transport; rule authoring is Scheme. The result is a validated catalog
for `Engine.open`, not permission to execute external tools.

```python
catalog = engine.read_rules("""(ascent-fragment
  (relation input ((value symbol?)))
  (relation output ((value symbol?)))
  ((output X) <-- (input X)))""")
```

Downstream consumers need the installed engine/API and Python, not `gxi` or a
Scheme toolchain. Building that engine remains a producer responsibility.

## Compiled API Build

CFFI recommends out-of-line API mode when compilation is available: the compiler
checks declarations against the real header, and the generated module avoids
rebuilding C declarations at import time. ABI-mode dlopen cannot offer the same
compile-time checking. See the [CFFI overview](https://cffi.readthedocs.io/en/latest/overview.html#main-mode-of-usage)
and [ABI/API comparison](https://cffi.readthedocs.io/en/latest/overview.html#abi-versus-api).

Build the normal Gerbil package and its AOT library first. The thin extension
builder does not rebuild Scheme or select another SDK:

```sh
python -m ascent_engine.api_build \
  --library "$ASCENT_ENGINE_LIBRARY" --header "$ASCENT_REPOSITORY/bindings/c/ascent.h" \
  --out "$ASCENT_EXTENSION_DIRECTORY" --cc "$GNU_CC"
PYTHONPATH="$ASCENT_EXTENSION_DIRECTORY" python -c \
  'from ascent_engine import Engine; e = Engine(); print(e.request({"operation":"describe"})); e.shutdown()'
```

The build environment needs CFFI and setuptools. `Engine()` requires the compiled
`_ascent_cffi` module; it never silently falls back. `Engine(library)` retains
explicit ABI-mode use for qualification/debugging. Backends cannot be mixed in
one process. Both routes use the same memory ownership and lifecycle code.

The builder verifies a producer sidecar when available, hashes header/library,
uses GNU GCC, and checks for input drift before recording its output. It repairs
the copied Darwin dylib's install name to `@rpath/libascent.dylib`; it does not
modify the live producer. Future producer builds set their final install name
while linking, rather than embedding a `.pending` path. The wrapper uses
`@loader_path` on Darwin and `$ORIGIN` on Linux. Source/header/producer consistency
without a sidecar remains unproven and is recorded as such.

## Ownership and Concurrency

- C owns result memory; Python copies it and releases it in `finally`, including errors.
- A session context closes its handle when Python raises an exception.
- Status failures become typed exceptions, not empty successful results.
- Main OS thread initializes and owns the one Gambit runtime; shutdown is terminal.
- A fork child cannot initialize, request or shut down an inherited runtime.
  Inherited atexit cleanup is skipped. Use a fresh spawned/exec process for a
  separate engine rather than reusing parent VM state after fork.
- CFFI's ability to release the GIL does not make this Scheme runtime thread-safe.
  Do not infer parallel engine access from Python thread support.
- Host subprocess exit status and signal ownership must survive embedding.
  Never treat a zero exit caused by stolen child status as a successful test.

These constraints are engine contracts, not limitations removed by choosing
API mode. See [CFFI thread safety](https://cffi.readthedocs.io/en/latest/overview.html#thread-safety)
and [CFFI memory ownership](https://cffi.readthedocs.io/en/latest/using.html).

## Distribution Boundary

This is a qualified local extension build, **not yet a portable binary wheel**.
The current Darwin library still links host OpenSSL, zlib and SQLite libraries.
Shipping it requires auditing/bundling those transitive dependencies, licenses,
wheel platform/deployment tags and relocation in a clean environment. Linux
needs its own clean native qualification. Never label this a pure-Python wheel.
See the [Python Packaging binary extension guide](https://packaging.python.org/en/latest/guides/packaging-binary-extensions/).

Qualification runs `engine_tests/test_binding_modes.py` and `test_review.py` in
fresh processes with `ASCENT_ENGINE_BACKEND=api` and the extension on PYTHONPATH,
then separately with `ASCENT_ENGINE_BACKEND=abi` and ASCENT_ENGINE_LIBRARY set.
They cover real C allocation release, typed errors, session cleanup, OS-thread
rejection, terminal shutdown, child exit propagation and evidence queries.
No end-to-end Scheme speedup, arbitrary-program proof or wheel portability is
claimed by these checks.
