# Native Build Ownership

`build.ss` declares the module, phase and native entry tasks with
`defbuild-script`. Gerbil `std/make` owns dependencies, compilation scheduling
and incremental decisions. Its native entry links the C ABI shared library;
there is no Python Scheme compiler or parallel phase build graph.

```sh
GERBIL_BUILD_CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null || getconf NPROCESSORS_ONLN)" GERBIL_PATH="$PWD/.gerbil" gxi bindings/build-entry.ss
PYTHONPATH="$PWD/python/src" python -m ascent_engine.build \
  --build-dir "$PWD/.gerbil" --output "$PWD/.gerbil/lib/libascent.so"
PYTHONPATH="$PWD/python/src" python -m ascent_engine.api_build \
  --library "$PWD/.gerbil/lib/libascent.so" --header bindings/c/ascent.h \
  --out "$PWD/.cache/ascent/cffi-api" --cc gcc
```

On Darwin, use `libascent.dylib` for the packaged filename and an explicit GNU
GCC executable for `--cc`. Normal native linker settings, including `LDFLAGS`,
belong to the `gxi build.ss` invocation, not the packager.
`bindings/build-entry.ss` is a Scheme loading boundary for generated
resources; it invokes the exported `build.ss` entry and declares no compilation
tasks of its own. The source inventory binds both files. It replaces temporary
diagnostic launchers, not Gerbil's compiler or build graph.
`CC` and `CFLAGS` are projected into those native compiler tasks by the existing
PackageSpec option resolver. Record its actual value with the chosen artifact;
different optimization settings are not interchangeable performance evidence.
`GERBIL_GCC` independently selects the executable link compiler in the upstream
driver; setting `CC` alone does not select that compiler. On Darwin, explicitly
bind it to the same GNU GCC and bind current native dependency search paths in
`LDFLAGS`. Stale Cellar paths and abandoned object locks from a timed-out build
are environment failures, not source correctness results. Use an isolated
output directory without importing abandoned locks; preserve failed outputs.
`GERBIL_BUILD_OPTIMIZE=0` selects `std/make`'s non-optimizing Gerbil compilation
setting for a separate correctness/debug build; the default remains optimized.
`GERBIL_BUILD_CORES` selects Gerbil's own scheduler concurrency; it does not
create another task scheduler. Choose it for the actual host resources.

After successful make, the producer records source and artifact hashes in
`bin/libascent.json`. Its metadata closure inventory lists existing compiler
outputs; it does not discover compilation tasks or judge timestamps. The
Python packager checks this receipt and copies its exact artifacts. The API
builder compiles only the CFFI C glue and performs the necessary shared-library
packaging. Neither command invokes `gxc`, `gsc` or `gxi`.

The embedded native engine consumes `.ssi` interfaces and compiler-generated
`.scm` resources through Gerbil's existing loader and raw-Scheme context. It
expands DSL text with the upstream `ascent` / `ascent-fragment` syntax. Python
loads text, calls this native API and owns session/timeout cleanup; it neither
imports the DSL as a Scheme module nor compiles it. Runtime opening, actual
queries, retained sessions and final cleanup require their own real tests;
a successful build or packaging receipt does not establish them.

Native Evidence modules also use this same loader/build boundary. Their
constructors and hygienic macros execute in Scheme, and whole upstream Programs
need not pass the finite JSON projection. See `evidence/README.md` for native
results, explanations and generation-bound ownership.

Frozen historical scripts and receipts may refer to the removed Python build
or `--relink` path. They are historical observations, not current build entry
points, and must not be rewritten as fresh qualifications.
