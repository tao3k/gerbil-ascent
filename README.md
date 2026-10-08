<!-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors -->
<!-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later -->

# gerbil-ascent

gerbil-ascent is a research implementation of relational reasoning in Gerbil.
It studies how checked Scheme programs can derive finite relations, retain
results across source changes, and return bounded evidence tied to exact
snapshots. Rust Ascent is a comparison oracle; Gerbil POO and POO Flow Core
provide the native foundation.

## Research directions

- **Language and semantics:** first-class relational programs and fragments,
  checked composition, finite higher-order operators, and the link from the
  Scheme compiler to formal models.
- **Evaluation and change:** fixed-point execution, indexes and storage,
  retained Sessions, source replacement, and measured update costs.
- **Reasoning evidence:** inert candidate rules, admission diagnostics,
  finite closure, founded support, and bounded ground nonmembership.
- **Time and context:** valid time, knowledge time, named causal cuts, and
  snapshot-bound temporal answers.

The checked Scheme language, evaluator, candidate boundary, and finite
temporal lens are implemented. Formal results cover selected abstract laws;
they do not yet prove the native compiler or runtime correct. Full Rust
replication, general deletion deltas, exhaustive provenance, and external
source or causal authority remain open research gates.

## Read the work

- [Native Library contract](docs/native-library-acceptance.org) — implemented
  language, admission, and result boundaries.
- [Feature design and assurance](docs/features/index.org) — implementation,
  paper correspondence, proofs and acceptance grouped by feature.
- [Research and proof audit](docs/scheme-research-proof-audit.org) — papers,
  code, formal results, and remaining obligations.
- [Agent inference research](docs/research/agent-inference/index.org) —
  candidate reasoning and model evaluation questions.
- [Temporal design](docs/temporal-causality-module-design.org) — implemented
  finite lens and broader temporal questions.
- [Rust parity matrix](docs/rust-parity.org) — differential qualification and
  the separate replication claim.

## Run

```sh
gerbil deps --install
just build
just test
```

`just oracle` runs the Rust comparison; `just performance` runs the
benchmark suite. See `just --list` for focused checks.

## Papers studied

This list brings together the papers examined in the
[related-work matrix](docs/related-work-matrix.org),
[Scheme DSL readings](docs/research/scheme-dsl/index.org),
[agent inference readings](docs/research/agent-inference/index.org), and
[temporal study](docs/temporal-causality-module-design.org).
The [code-anchored research screen](docs/research/agent-inference/2026-logic-ai-screen.org)
ranked them by the question each can test in this implementation. Recent
model papers lead the inference section; older PL work remains central where
it supplies a precise language, fixed-point or incremental-evaluation law.
The [reasoning-language and formal agenda](docs/research/agent-inference/reasoning-language-formal-agenda.org)
connects ASCENT, MRR, Lean and TLA+ without treating their boundaries as proved integration.
The [pinned Wikidata fixture](docs/research/agent-inference/wikidata-scope-wd26.org)
starts the executor check for branch-scoped exclusion over a finite real-KG extract.

### Model reasoning and executable inference: current evidence

- [LLM-MatLogic: Executable Exchange Contracts for Knowledge-Graph Query Answering with Scoped Negation](https://proceedings.mlr.press/v306/miao26e.html) (ICML 2026) — real KG questions; scope and witness correctness.
- [DatalogBench: Evaluating Large Language Models on Text-to-Datalog Synthesis](https://arxiv.org/abs/2609.37233) (2026 preprint) — generated recursive rules checked by execution, with preprint and dialect limits.
- [IRIS: LLM-Assisted Static Analysis for Detecting Security Vulnerabilities](https://proceedings.iclr.cc/paper_files/paper/2025/file/582d4e27fa24168f3af1f4582655034b-Paper-Conference.pdf) (ICLR 2025) — real-code candidate specifications and CodeQL results; adjacent language and high false-alert cost.

[BRINK](https://aclanthology.org/2026.eacl-long.114/) (EACL 2026) is a
useful incomplete-KG evaluation comparator, not a semantic oracle: it
removes observed facts while preserving rule-body paths, but its rules are
mined with confidence thresholds rather than established as universal laws.

### Relational languages and evaluation: semantic foundations

- [Datafun: a Functional Datalog](https://doi.org/10.1145/3022670.2951948) (2016) — monotonicity and finite-height fixed points.
- [Seminaïve Evaluation for a Higher-Order Functional Language](https://doi.org/10.1145/3371090) (2020) — change semantics for higher-order rules.
- [Bring Your Own Data Structures to Datalog](https://doi.org/10.1145/3622840) (2023) — concrete/delta semantics for specialized relations.
- [Mono Types – First-Class Containers for Datalog](https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.ECOOP.2025.33) (ECOOP 2025) — mechanized monotone container observations and program-analysis experiments.
- [Seamless Deductive Inference via Macros](https://doi.org/10.1145/3497776.3517779) (2022) — the Rust Ascent language and comparison baseline.
- [Flix: A Design for Language-Integrated Datalog](https://doi.org/10.1145/3763126) (2025) — first-class program and private predicate boundaries.
- [FlowLog: Efficient and Extensible Datalog via Incrementality](https://www.vldb.org/pvldb/vol19/p361-zhao.pdf) (PVLDB 2025; VLDB 2026) — recursive plan and incremental engine experiments.
- [Scallop: A Language for Neurosymbolic Programming](https://doi.org/10.1145/3591280) (2023) — weighted and differentiable semantics for a separate training path.
- [Soufflé: On Synthesis of Program Analyzers](https://souffle-lang.github.io/pdf/cav16.pdf) (2016)
- [Differential dataflow](https://www.cidrdb.org/cidr2013/Papers/CIDR13_Paper111.pdf) (2013)
- [DBSP: Automatic Incremental View Maintenance for Rich Query Languages](https://www.vldb.org/pvldb/vol16/p1601-budiu.pdf) (2023)
- [Optimised Maintenance of Datalog Materialisations](https://doi.org/10.1609/aaai.v32i1.11554) (2018)
- [Better Together: Unifying Datalog and Equality Saturation](https://doi.org/10.1145/3591239) (2023)
- [Formulog: Datalog for SMT-Based Static Analysis](https://doi.org/10.1145/3428209) (2020)
- [µKanren: A Minimal Functional Core for Relational Programming](https://www.schemeworkshop.org/2013/papers/HemannMuKanren2013.pdf) (2013)
- [Fixpoints for the Masses: Programming with First-Class Datalog Constraints](https://plg.uwaterloo.ca/~olhotak/pubs/oopsla20c.pdf) (2020)
- [Datalog with First-Class Facts](https://www.vldb.org/pvldb/vol18/p651-micinski.pdf) (PVLDB 2024; VLDB 2025)

### Provenance and time

- [Provenance Semirings](https://www.cs.ucdavis.edu/~green/papers/pods07.pdf) (2007)
- [Revisiting Semiring Provenance for Datalog](https://proceedings.kr.org/2022/10/kr2022-0010-bourgaux-et-al.pdf) (2022)
- [PUG: A Framework and Practical Implementation for Why & Why-Not Provenance](https://arxiv.org/abs/1808.05752) (2018)
- [Provenance for Large-scale Datalog](https://arxiv.org/abs/1907.05045) (2019)
- [Dedalus: Datalog in Time and Space](https://www2.eecs.berkeley.edu/Pubs/TechRpts/2009/EECS-2009-173.html) (2009)
- [Causes and Explanations: A Structural-Model Approach. Part I: Causes](https://doi.org/10.1093/bjps/axi147) (2005)

## Credits

The papers above retain their authors' and publishers' rights. The Rust
[Ascent project](https://github.com/s-arash/ascent) is the test oracle and is
licensed separately under MIT. Repository-authored code is licensed under
`Apache-2.0 AND LGPL-2.1-or-later`; see [LICENSE](LICENSE).
