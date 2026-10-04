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
finite views, admission, Sessions, and relation operators. Native
`where` and `compute` clauses accept bound `?variables`, scalar
literals, and explicit `(value expression)` captures. Captures are fixed
when the program or fragment is constructed and checked again at admission.
The historical [`ascent` form](docs/scheme-syntax.org) remains in `program/syntax.ss` for
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
The [native Library admission contract](docs/native-library-acceptance.org)
separates the Scheme language gate from the historical full Rust replication
claim and records the next semantic and performance evidence.
The Scheme-native rule surface in `program/scheme-language.ss`,
finite relation operator descriptors in `program/operator.ss`, and
bounded inert candidate boundary in `candidate/reasoning.ss` share the
POO rule evaluator. Candidate inspection in `candidate/program.ss` accepts
ordered atoms, checked negation, fixed scalar filters/computations and
count/sum/min/max reductions as inert data; receipts expose complete rows
with the exact graph witness/cut case as a narrow explanation. For an
inspected positive proposal with fixed `where` and `compute` clauses,
`candidate/provenance.ss` can attach
a bounded, replayable rule-instance proof DAG to a completed query. Its
source and hypothetical candidate nodes remain distinct; negation and
reduction use a separate finite stratified proof when the caller supplies an
explicit fourth work-budget argument to `reasoning-attempt`. The optional
`reasoning-receipt-stratified` value contains a finite closure certificate,
one founded support for each nonempty query row when supported, and an explicit
status. `reasoning-verify-stratified-receipt` rechecks a completed proof against
the bound source and candidate. `reasoning-verify-finite-receipt` also checks
the finite closure when a query answer is empty. A bounded or unsupported
proof leaves the native completed answer intact. Neither proof is exhaustive
provenance.
For a missing ground target under finite positive rules with the same fixed
scalar clauses,
`candidate/nonmembership.ss` separately emits a
bounded per-relation closed-set certificate; its verifier checks input
coverage, rule closure and target absence relative to the named snapshot.
Candidate and snapshot data pass a bounded iterative preflight before
parsing or hashing; cycles and executable leaves are rejected. Inert
rejected candidates retain a content digest, and
`reasoning-receipt-bound?` checks whether feedback still belongs to the
same local source generation and proposal. The scripted feedback test
covers a rejected proposal, a valid wrong join, its correction, source
withdrawal and an isolated hypothetical edge against an independent
finite graph model. This binding check does not authenticate the source
or prove that the proposal captures a caller's intended meaning.

The operator compiler supports source, union,
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
`relational-op-retained-replace-sources!` replaces multiple exported
sources in one completed transaction, including the transformer's
generated input label; failed validation or solving leaves the earlier
state available. Withdrawal and batch replacement rebuild the native
source snapshot, without claiming an incremental deletion algorithm.
For a composed program, `relational-session-transaction!` accepts
`(fragment label rows)` updates across fragments and returns one solved
snapshot. A direct named program uses `relational-program-transaction!`
with `(name . rows)` updates. The combined qualification changes
recursive edges, a negated source, finite view rows, grouping roots and
lattice seeds together, checking a separate finite model and failure
rollback. The [deletion research note](docs/research/scheme-dsl/deletion-h18.org)
records the evidence needed before optimizing withdrawal.
The [retained Session receipt](docs/research/scheme-dsl/e4-retained-session.org)
checks all 64 three-node graph masks through append, duplicate append,
withdrawal and two-source nested closure, and records a matched local
update-latency probe for the earlier single-source interface.
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
the candidate grammar. The
[positive proof contract](docs/research/scheme-dsl/positive-provenance.org)
states the supported Why subset. The
[ground Why-Not contract](docs/research/scheme-dsl/positive-nonmembership.org)
records the distinct nonmembership proof and closed-world limit.
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

## Test execution

`just test` discovers qualification modules and runs two phases. The explicitly
reviewed semantic modules in `tools/test_execution.py` run in separate Gerbil
processes. Native `std/test` still executes each module's suites and Cases in
order. After all parallel workers finish, exclusive modules run one at a time.
New modules default to exclusive execution until reviewed.

`GERBIL_BUILD_CORES` supplies the default concurrency through ASP's native
builder capacity API; its native host CPU fallback applies when unset.
`just test 2` overrides only test concurrency. The worker count is the smaller
of configured capacity and the number of admitted modules. Each process keeps
the existing 1 GiB heap limit and native Case profiles.

Exclusive modules cover custom duration/GC profiles, timeout and timing tests,
internal multithreading, and the large exhaustive operator/library fixtures.
Builds and performance recipes use the same exclusive file lease, including
nested calls. Cancellation sends TERM to active workers, escalates to KILL
after a shared five-second grace period, and reaps them before returning.

Per-module native logs, phase summaries, and a complete suite JSON receipt live
under `.gerbil/test-execution/`. The suite checks exact discovered-module
coverage and reports failure if any worker fails. `test-file` also requires
nonempty native Cases, exact module completion, harness completion, and final
`OK`, rejecting native error and overflow markers even on exit zero.
`just test-serial` retains the older bounded batch path for comparisons.

`just performance` and `just performance-scenario NAME` build the complete
production module inventory into a private native library before sampling.
All production imports must resolve to that library; nested scenarios reuse
the verified snapshot under the same exclusive lease. Source, fixture,
dependency and native artifact changes reject the receipt. Compilation is
outside the scenario timer. Functional fixtures keep their source lookup
by default. The execution-mode diagnosis and original SS results are recorded
in the [native qualification report](t/performance/session-lifecycle/README.org).

Measured full-suite comparisons and the admission rationale are recorded in
[t/performance/suite-execution/README.org](t/performance/suite-execution/README.org).
The [declaration compilation receipt](docs/declaration-compilation-benchmark.org)
compares cold construction, cached construction, and complete solves across the
planning refactor without changing the original scenario thresholds.

## Positive rule execution

The evaluator compiles supported complete positive rules into cached numeric
slot plans. Each engine owns its variable frames and uses the existing index
and output admission boundaries. Dirty fixed-point runs reuse their pending
vectors, deduplication tables and interpreter closures across rounds. Rules
with callbacks retain the general interpreter. One-shot engines allocate Session update closures only when a
Session is requested. Qualification and matched complete-solve measurements,
including performance limits and failed original SS gates, are recorded in
[t/performance/positive-plan/README.org](t/performance/positive-plan/README.org).

The subsequent [execution workspace qualification](t/performance/execution-workspace/README.org)
compares the complete recursive and retained execution paths with the preceding
commit, including latency limits and original SS gate results.

The built-in hash index now uses one physical access boundary for construction,
incremental extension and lookup. Ordered keys traverse each row once, and
bucket updates avoid temporary closures. Custom providers retain dispatch,
validation and callback order. Full-solve allocation measurements, timing limits
and native qualification are recorded in the
[index lifecycle report](t/performance/index-lifecycle/README.org).

Retained engines now publish persistent row views on demand. Unchanged
relations reuse their ordered view, while unread intermediate results avoid
copying row headers. Historical results remain stable after later appends,
replacement and timeout resume. Public row reads still return ordinary lists.
Complete-output allocation measurements and timing limits are recorded in the
[result publication report](t/performance/result-publication/README.org).

## Bounded relation execution

Composition, delta steps, closure and shortest distances share a prepared
relation view. Dense source traversal and direct neighbor loops reuse its
private adjacency; sparse sources retain native UIntTrieSet traversal. Public
neighbor overrides and immutable snapshot behavior remain covered by native
qualification. Matched gains, small-input costs, and the original SS gate
results are recorded in the [relation execution report](t/performance/relation-materialization/README.org).
