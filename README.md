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

This list brings together the primary papers in the
[related-work matrix](docs/related-work-matrix.org),
[Scheme DSL readings](docs/research/scheme-dsl/index.org),
[agent inference readings](docs/research/agent-inference/index.org), and
[temporal study](docs/temporal-causality-module-design.org).

### Relational languages and evaluation

- [Seamless Deductive Inference via Macros](https://doi.org/10.1145/3497776.3517779) (2022)
- [Bring Your Own Data Structures to Datalog](https://doi.org/10.1145/3622840) (2023)
- [Soufflé: On Synthesis of Program Analyzers](https://souffle-lang.github.io/pdf/cav16.pdf) (2016)
- [Differential dataflow](https://www.cidrdb.org/cidr2013/Papers/CIDR13_Paper111.pdf) (2013)
- [DBSP: Automatic Incremental View Maintenance for Rich Query Languages](https://www.vldb.org/pvldb/vol16/p1601-budiu.pdf) (2023)
- [Optimised Maintenance of Datalog Materialisations](https://doi.org/10.1609/aaai.v32i1.11554) (2018)
- [Datafun: a Functional Datalog](https://doi.org/10.1145/3022670.2951948) (2016)
- [Better Together: Unifying Datalog and Equality Saturation](https://doi.org/10.1145/3591239) (2023)
- [Formulog: Datalog for SMT-Based Static Analysis](https://doi.org/10.1145/3428209) (2020)
- [µKanren: A Minimal Functional Core for Relational Programming](https://www.schemeworkshop.org/2013/papers/HemannMuKanren2013.pdf) (2013)
- [Fixpoints for the Masses: Programming with First-Class Datalog Constraints](https://plg.uwaterloo.ca/~olhotak/pubs/oopsla20c.pdf) (2020)
- [Seminaïve Evaluation for a Higher-Order Functional Language](https://doi.org/10.1145/3371090) (2020)
- [Flix: A Design for Language-Integrated Datalog](https://doi.org/10.1145/3763126) (2025)

### Provenance and time

- [Provenance Semirings](https://www.cs.ucdavis.edu/~green/papers/pods07.pdf) (2007)
- [Revisiting Semiring Provenance for Datalog](https://proceedings.kr.org/2022/10/kr2022-0010-bourgaux-et-al.pdf) (2022)
- [PUG: A Framework and Practical Implementation for Why & Why-Not Provenance](https://arxiv.org/abs/1808.05752) (2018)
- [Provenance for Large-scale Datalog](https://arxiv.org/abs/1907.05045) (2019)
- [Dedalus: Datalog in Time and Space](https://www2.eecs.berkeley.edu/Pubs/TechRpts/2009/EECS-2009-173.html) (2009)
- [Causes and Explanations: A Structural-Model Approach. Part I: Causes](https://doi.org/10.1093/bjps/axi147) (2005)

### Model reasoning and inference

- [DatalogBench: Evaluating Large Language Models on Text-to-Datalog Synthesis](https://arxiv.org/abs/2609.37233) (2026)
- [Logic-LM: Empowering Large Language Models with Symbolic Solvers for Faithful Logical Reasoning](https://aclanthology.org/2023.findings-emnlp.248/) (2023)
- [LINC: A Neurosymbolic Approach for Logical Reasoning by Combining Language Models with First-Order Logic Provers](https://aclanthology.org/2023.emnlp-main.313/) (2023)
- [Call Me When Necessary: LLMs can Efficiently and Faithfully Reason over Structured Environments](https://aclanthology.org/2024.findings-acl.254/) (2024)
- [Interleaving Retrieval with Chain-of-Thought Reasoning for Knowledge-Intensive Multi-Step Questions](https://aclanthology.org/2023.acl-long.557/) (2023)
- [ReAct: Synergizing Reasoning and Acting in Language Models](https://arxiv.org/abs/2210.03629) (2023)
- [Tree of Thoughts: Deliberate Problem Solving with Large Language Models](https://papers.nips.cc/paper_files/paper/2023/hash/271db9922b8d1f4dd7aaef84ed5ac703-Abstract-Conference.html) (2023)
- [Scallop: A Language for Neurosymbolic Programming](https://doi.org/10.1145/3591280) (2023)

## Credits

The papers above retain their authors' and publishers' rights. The Rust
[Ascent project](https://github.com/s-arash/ascent) is the test oracle and is
licensed separately under MIT. Repository-authored code is licensed under
`Apache-2.0 AND LGPL-2.1-or-later`; see [LICENSE](LICENSE).
