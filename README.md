<!-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors -->
<!-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later -->

# gerbil-ascent

Scheme-native ASCENT implementation built on Gerbil POO and POO Flow Core.
`gerbil.pkg` declares POO Flow Core for shared POO contracts and ASP for the
Building API and standard SS benchmark profile. The ASCENT package owns its
Gerbil build and 1000-sample SS qualification; POO Flow checks only pinned
consumer integration.
Each top-level directory is a Gerbil module namespace:

| Namespace | Current responsibility |
| --- | --- |
| `:gerbil-ascent/program/*` | Typed POO rule declarations and stratified evaluation |
| `:gerbil-ascent/core/*` | Indexed binary evaluation path |
| `:gerbil-ascent/table/*` | Binary relation indexes and projections |
| `:gerbil-ascent/candidate/*` | Bounded inert candidate evaluation and selected support projection |
| `:gerbil-ascent/interface/*` | Inert request projection |

`program/interface.ss` exports the native
[`relational-program` and `relational-fragment` forms](docs/scheme-relational-language-design.org)
with checked scalar capture, negation, reductions, lattice declarations,
finite views, admission, Sessions, and relation operators. The historical
[`ascent` form](docs/scheme-syntax.org) remains in `program/syntax.ss` for
the Rust parity qualification corpus; it is no longer re-exported by the
public interface. The lower-level POO API still exposes
`relation`, `lattice`, `atom`, `negation`, `guard`, `binding`, `aggregate`,
and Standard Library iterable `generator` clauses with scalar or tuple outputs. A slot Generic lowers each clause to a
private execution plan; count, sum, min, max, mean, and custom aggregate
procedures run over matched tuples. Lattice declarations join the last column
for equal prefix keys and propagate improvements through the same fixed point.
Generic relation clauses plan bound columns and use a cached table index when
the relation has at least 32 rows. `table/interface.ss` exposes a POO index
Provider; a custom provider can replace the physical index without changing
the rule program.
The BYODS storage Provider creates private state for each relation evaluation.
The `eqrel` implementation maintains component membership and emits new
cross-component facts when an edge joins two components.
The `trrel` and `trrel_uf` implementations index known predecessors and
successors per relation run, preserving explicit self facts and grouped keys.
Guards, bindings, and generators declare their input variables explicitly, and rule
bodies check bindings in source order. The evaluator reads validated clause
slots once per run before iterating relation rows.

`gerbil-ascent-open-session` retains relation rows, indexes, BYODS state, and
semi-naive deltas across calls to `gerbil-ascent-session-run`. After the first
run, `gerbil-ascent-session-append-source!` accepts source rows. Positive
relation-only programs use retained deltas; programs with negation or
aggregation re-evaluate the accepted source snapshot. Each run returns a
stable POO result snapshot; an unchanged run returns its previous result.
`gerbil-ascent-session-replace-source!` atomically replaces one relation's
declared source rows, including replacement with an empty list. It recomputes
the fixed point and leaves earlier result snapshots intact.
Positive source relation updates may feed recursive lattices. Direct lattice
source values join by key; after a direct lattice append, the session evaluates
the accepted source snapshot so rule-derived values and downstream lattices
reach the same fixed point as a fresh run. Rust Ascent 0.8.0 may expose raw
same-key source tuples and different rows after a repeated mixed-source run;
the Rust oracle records those implementation differences. The one-shot
`gerbil-ascent-evaluate-program` uses the same evaluator.

For rule-level diagnostics, pass `measure-rule-times?: #t` to either
`gerbil-ascent-open-session` or `gerbil-ascent-evaluate-program`. Each result
then carries a `rule-time-nanoseconds` list in declaration order. The default
result has `#f` in that slot and does not read a clock for each rule. This is
the Scheme counterpart of Rust Ascent's `#![measure_rule_times]`; timing
values are platform measurements and are not compared for exact equality.
Each result also exposes a lazy POO `relation-sizes` slot. It counts that
result's immutable relation snapshots when called; the selected empty,
single and duplicate-source sizes match Rust Ascent's generated
`relation_sizes_summary()` API.

`t/` contains Scheme qualification; `rust/ascent-oracle/` contains the
test-only Rust Ascent differential oracle. The [parity matrix](docs/rust-parity.org)
tracks the unfinished Rust 0.8.0 feature surface and documented fixed-point
divergences. The [replication checklist](docs/replication-checklist.org)
tracks the remaining executable closure gates and the final-head admission.
The Rust comparison documents the current implementation; it is not a
compatibility target for the proposed
[Scheme relational language](docs/scheme-relational-language-design.org).
The Scheme-native rule surface in `program/scheme-language.ss`,
finite relation operator descriptors in `program/operator.ss`, and
bounded inert candidate boundary in `candidate/reasoning.ss` share the
POO rule evaluator. The operator compiler supports source, union,
equijoin, fixed equality selection, projection, finite mapping and
positive fixed points. An operator graph can now become a fresh fragment
and compose with native rules; a first-class relation transformer has an
explicit application node and a complete finite reference interpreter.
`relational-op-reference-change` compares two completed reference results.
`relational-op-delta-change` propagates positive input insertions through
the finite operator graph and advances recursive results by a frontier.
The two paths are checked against an independent finite graph model.
The [paired E4 probe](docs/research/scheme-dsl/e4-positive-change.org)
records join counts and exploratory timing for chain and star cases;
it does not establish a general speed advantage.
`relational-op-open-retained` also admits a first-class transformer
once into the native Session. Checked append and replacement return
before/after output differences while preserving completed snapshots.
The [retained Session receipt](docs/research/scheme-dsl/e4-retained-session.org)
checks all 64 three-node graph masks through append, duplicate append
and withdrawal, and records a matched local update-latency probe.
The rule surface also supports explicit scalar
capture, stratified negation, checked count/sum/min/max reductions and
checked min/max lattices. `relational-admit/report` returns a typed
diagnostic with the planner's rule and clause position on rejection.
The integrated qualification exercises a recursive operator fragment,
views, negation, reduction, lattices, retained source insertion and
withdrawal, and prior-result
stability. The 64-graph finite-model corpus checks reference meaning,
direct compilation, fragment composition and source-growth change.
General typed higher-order change, deletion deltas and arbitrary host
callbacks remain in the
[language design](docs/scheme-relational-language-design.org). The
[LLM reasoning Library plan](docs/llm-reasoning-library-plan.org) records
the candidate grammar and the narrow graph witness/cut evidence contract.
POO Flow
consumes this package as a pinned submodule. MRR owns the semantic adapter
and admission of its own evidence.

The [related-work matrix](docs/related-work-matrix.org) maps the Ascent papers
and adjacent research on incremental updates, monotonicity, equality,
constraints, and provenance to concrete parity and Agent research questions.
The [temporal-causality design gate](docs/temporal-causality-module-design.org)
defines a proposed snapshot-bound Scheme module and its executable research
gate; it does not describe an implemented API.

Scheme qualification extends Core's Observability Case profile with
ASCENT-specific memory and duration budgets; it does not own a test runner.

```sh
gerbil deps --install
gerbil build
just test
just oracle
just performance
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
The other cited papers and their authors are listed in the
[related-work bibliography](docs/related-work-matrix.org).

The Scheme implementation and repository-authored qualification code are
copyright © 2026 tao3k team and Contributors and are licensed under
`Apache-2.0 AND LGPL-2.1-or-later`, as stated in [LICENSE](LICENSE) and
the source file SPDX headers. That project license does not change the
upstream project's license or the papers' rights.
