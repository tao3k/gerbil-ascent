# Compiled Algorithm Reuse

## Primary Direction

ASCENT owns its DSL, relations, algorithms and inference semantics.
`gerbil-scheme-rust` owns reusable ABI types, owned values, foreign callable and
component lifetimes. Rust is the thin execution host; Python transports parameters,
identity and results. A Rust host does not justify rewriting Scheme algorithms,
writing a second interpreter, or generating Rust for every missing foreign export.

Reuse existing compiled C-compatible algorithms when they actually have independent
initialization/allocation contracts. Preserve exact source-to-artifact identities.
The consumer installs a wheel, not a Gerbil SDK or compile workflow. No automatic
backend fallback is permitted.

## Current Export Audit

`bindings/c/runtime.c:ascent_runtime_init` calls `___setup`, and
`ascent_request` calls `ascent_scheme_dispatch` on its registered owner thread.
The Scheme dispatcher is defined by `interface/c-api.ss`. This is a real C ABI,
but not a VM-independent algorithm entry. Calling it while suppressing runtime
initialization is not a supported optimization or a valid migration.

The new upstream owned C ABI contract admits independent producer allocations,
compiled callables and transactional component states. Its C qualification fixture
does not establish that these rich ASCENT operations have independent exports.
The outstanding work is the actual producer boundary, not more handwritten Rust
DSL algorithms. Retain the existing failures until the corresponding producer
and installed-wheel controls genuinely pass.

The unqualified build-time Rust callable draft was disconnected from
`ascent-python` in this change. Its generated closure test cannot serve as C ABI
reuse evidence. Earlier typed-IR and Rust-path results retain their own identities;
they are not relabeled as current compiled C producer qualification.

## Acceptance Remains Separate

Require actual DSL/closure/component behavior, no Scheme VM entry, complete
per-path source hashes, wheel installation without SDK/build directories,
consumer regressions, sealed review, full current graph and published dependency
identity. Preserve prior failures and execution caps. None of these gates is
closed merely because generic bridge tests pass. No new wheel or Git publication
is qualified by the owned C ABI test alone.

## Fixed Core Boundary And Diagnosis

`rust/ascent-c-abi` now forwards the existing Library Core through a fixed
`ascent_core_open` owned callable. It does not make arbitrary Scheme procedures
VM-independent. The Python host uses the upstream owned ABI value and callable
types, not a generic closure producer. `Engine.core_evidence` is explicit;
ordinary facade migration and full consumer qualification remain separate.

Enable `diagnostics=True` to measure Rayon pool creation, DSL read/lowering,
initial admission, replacement/inference, result snapshot, graph construction,
ABI decoding/encoding and Python projection. Timings are the latest observation
per boundary, not proof or admission authority. Nested timings must not be added
as independent costs. Worker count alone is not evidence of parallel speedup.

`run(result_format="typed-rows")` explicitly avoids scalar graph inflation while
preserving scalar types and complete object graphs/namespaces for shared, cyclic
and opaque values. The default `graph` representation remains explicit; unknown
formats are rejected, not silently substituted. Both formats execute the same
Core algorithm and native fact-budget accounting.

Run `workbench/src/ascent_workbench/benchmark_core_c_abi_rayon.py` against an installed wheel for alternating
one/four-worker measurements and graph/typed-row transport controls. It compares
complete answers, identical input/source digests and the complete source inventory
before/after. Large-output and compute-heavy small-output workloads are separate:
output encoding can dominate the former even when inference itself accelerates.
These workload measurements do not establish complete workflow performance,
arbitrary DSL coverage or Git publication qualification.
