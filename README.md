<!-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors -->
<!-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later -->

# gerbil-ascent

gerbil-ascent is a logical programming Library for checked rule declarations,
queries, fixed-point evaluation, incremental source maintenance and derivation
provenance. Scheme owns the native language and POO declarations; the Rust and
Python bindings expose the same bounded relational contracts.

Python consumers use `Engine.dsl`, `Engine.rules`, retained rule sessions and
owned results. Trusted Scheme execution is explicit. Source identity and a
recorded derivation do not authenticate external facts or authorize effects.

Application Evidence, Clue, Trajectory, model conversations, budget accounting
and model studies are owned by [POO Flow](https://github.com/tao3k/poo-flow).
Those APIs have been removed here. Consumers migrate directly to
`poo_flow_runtime.reasoning`; no compatibility facade is provided.

The engine retains generic founded support, nonmembership, source-generation
invalidation and proof replay. These describe rule execution, independently of
an application's interpretation of a result as evidence.

See [the migration boundary](docs/library-boundary.org), the
[native Library contract](docs/library-acceptance.org) and the
[Rust parity matrix](docs/rust-parity.org). Abstract Lean/Quint models and native
acceptance remain separate obligations.

## Run

```sh
gerbil deps --install
just build
just test
```

`just oracle` runs the Rust comparison; `just performance` runs the
benchmark suite. See `just --list` for focused checks.

## Research

The engine studies logical programming, BYODS relation implementations, retained
sessions, delta maintenance and derivation provenance. See the
[Scheme DSL readings](docs/research/scheme-dsl/index.org),
[related-work matrix](docs/related-work-matrix.org) and
[feature assurance](docs/features/index.org). Model efficacy and application
Evidence research are maintained downstream in POO Flow.
