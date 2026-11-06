# Declarative DSL and Precompiled Graph Contract

`Engine.dsl(source, constructor=None, trusted=True)` opens a fixed Core C ABI
Evidence session. It admits declaration data and statically checked relation
rules, not arbitrary Scheme programs. Its result is a `CoreSession`, not an
ordinary procedure module. Standalone ordinary procedure modules, mutable Scheme
execution, imports and unsupported executable forms fail admission. Pure helpers
and hygienic macros may lower statically into the declared closed kernels; they
do not acquire a runtime procedure-call interface. There is no VM or fallback.

`Engine.core_graph(graph, trusted=True)` binds parameters to maintenance-generated
Graph algorithms already owned by the Library. The capture contains:

- `algorithm`: `projection` or `transitive`.
- `source`, `width`, `rows`, `output`: the actual input and result relation.
- `captures`: `columns` for projection, an empty object for transitive.

These paths call the existing `make_projection_graph` and
`make_transitive_graph` algorithms generated from `program/rust-execution.ss` at
Library build time. No Scheme compiler or SDK is invoked by a wheel consumer.
The fixed C ABI owns the resulting retained Core session. Source withdrawal,
rollback, immutable result observations and exact owner closure use the existing
Core algorithms and gerbil-scheme-rust ownership types.

This is a fixed precompiled closure contract, not a generic closure producer:
callers cannot provide executable bodies or invoke arbitrary export names.
Every graph capture, column and width is validated before opening the owner.

## Evidence Boundaries

This contract change was explicitly approved instead of runtime arbitrary Scheme
definitions. Old ordinary-procedure tests must be preserved as historical
contract evidence; unsupported behavior must not be silently presented as current
capability. Closed vector `match` now lowers shape checking and field binding to
the Library's precompiled object operators. `for` accepts finite `list` generators
of explicit `vector` rows whose expressions use admitted closed operators; empty
generators remain empty derived relations, not writable sources. Disjunction
uses explicit `or/and` branches. Branch expansion retains the existing 256-rule
structure limit. Unknown callbacks, nested/procedural patterns and generators
outside this declared contract fail, never execute or fall back.

Vector references preserve shared/cyclic Graph namespaces; dynamic fields flowing
into typed heads are checked before publication. Failure does not publish partial
answers. Proof replay uses the same owned object primitives under its separate
step budget. These are closed relation kernels, not a Scheme interpreter.

Current local wheel receipts are not Git publication or complete consumer
qualification. Neither a C ABI flag nor a local test establishes those claims.
