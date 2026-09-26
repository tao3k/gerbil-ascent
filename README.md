<!-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors -->
<!-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later -->

# gerbil-ascent

Scheme-native ASCENT implementation built on Gerbil POO and POO Flow Foundation.
`gerbil.pkg` declares Foundation as its sole direct package dependency;
Foundation supplies the POO package used by the Scheme modules. The separate
SS benchmark qualification uses ASP from the development test environment.
Each top-level directory is a Gerbil module namespace:

| Namespace | Current responsibility |
| --- | --- |
| `:gerbil-ascent/program/*` | Typed POO rule declarations and stratified evaluation |
| `:gerbil-ascent/core/*` | Indexed binary evaluation path |
| `:gerbil-ascent/table/*` | Binary relation indexes and projections |
| `:gerbil-ascent/candidate/*` | Experimental candidate and support projection |
| `:gerbil-ascent/interface/*` | Inert request projection |

`program/` exposes POO `relation`, `lattice`, `atom`, `negation`, `guard`, `binding`, `aggregate`,
and finite-list `generator` clauses. A slot Generic lowers each clause to a
private execution plan; count, sum, min, max, mean, and custom aggregate
procedures run over matched tuples. Lattice declarations join the last column
for equal prefix keys and propagate improvements through the same fixed point.
Generic relation clauses plan bound columns and use a cached table index when
the relation has at least 32 rows. `table/interface.ss` exposes a POO index
Provider; a custom provider can replace the physical index without changing
the rule program.
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

## Credits and copyright

This project builds on the research ideas and published semantics of Ascent:

- Arash Sahebolamri, Thomas Gilray, and Kristopher Micinski,
  [“Seamless Deductive Inference via Macros”](https://doi.org/10.1145/3497776.3517779),
  *CC 2022*.
- Arash Sahebolamri, Langston Barrett, Scott Moore, and Kristopher Micinski,
  [“Bring Your Own Data Structures to Datalog”](https://doi.org/10.1145/3622840),
  *Proceedings of the ACM on Programming Languages, OOPSLA2 2023*.

The differential oracle depends on the upstream
[Ascent Rust project](https://github.com/s-arash/ascent) and
`ascent-byods-rels` 0.8.0. Copyright in that project belongs to its
individual contributors; its [source license is MIT](https://github.com/s-arash/ascent/blob/master/LICENSE).
The papers retain their authors' and publishers' rights. Citations here
acknowledge their research; the papers are not redistributed in this repository.

The Scheme implementation and repository-authored qualification code are
copyright © 2026 tao3k team and Contributors and are licensed under
`Apache-2.0 AND LGPL-2.1-or-later`, as stated in [LICENSE](LICENSE) and
the source file SPDX headers. That project license does not change the
upstream project's license or the papers' rights.
