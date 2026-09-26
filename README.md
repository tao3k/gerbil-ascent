<!-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors -->
<!-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later -->

# gerbil-ascent

Scheme-native ASCENT implementation built on Gerbil POO and POO Flow Foundation.
`gerbil.pkg` declares Foundation as its sole direct package dependency;
Foundation supplies the POO and ASP packages used by the Scheme modules.
Each top-level directory is a Gerbil module namespace:

| Namespace | Current responsibility |
| --- | --- |
| `:gerbil-ascent/program/*` | Typed POO rule declarations and stratified evaluation |
| `:gerbil-ascent/core/*` | Indexed binary evaluation path |
| `:gerbil-ascent/table/*` | Binary relation indexes and projections |
| `:gerbil-ascent/candidate/*` | Experimental candidate and support projection |
| `:gerbil-ascent/interface/*` | Inert request projection |

`program/` exposes POO `atom`, `negation`, `guard`, `binding`, and finite-list `generator` clauses.
Guards, bindings, and generators declare their input variables explicitly, and rule
bodies check bindings in source order. The evaluator reads validated clause
slots once per run before iterating relation rows.

`t/` contains Scheme qualification; `rust/ascent-oracle/` contains the
test-only Rust Ascent differential oracle. The [parity matrix](docs/rust-parity.org)
tracks the unfinished Rust 0.8.0 feature surface. Complete Scheme parity is
the gate before new Agent-specific extensions. POO Flow consumes this package
as a pinned submodule. MRR owns the semantic adapter and admission of its
own evidence.

Scheme qualification extends Foundation's Observability Case profile with
ASCENT-specific memory and duration budgets; it does not own a test runner.

```sh
gerbil deps --install
gerbil build
just test
just oracle
```

The Rust oracle is a qualification dependency, not part of the Scheme runtime.
